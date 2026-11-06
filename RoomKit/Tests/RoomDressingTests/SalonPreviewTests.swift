import CoreGraphics
import Foundation
import ImageIO
import RoomModel
import Testing
import simd
@testable import RoomDressing

/// Opt-in end-to-end check of the colouring on real photos: tessellates the
/// walls and floor of a saved scan and colours them from the probe's photos
/// (same ARKit session, so same world frame). Writes `realistic.mesh` into
/// `SALON_OUT`.
///
/// `SALON_ROOM=<room folder> SALON_PROBE=<probe folder> SALON_OUT=<folder> swift test --filter salonPreview`
@Test(.enabled(if: ProcessInfo.processInfo.environment["SALON_PROBE"] != nil))
func salonPreview() throws {
    let env = ProcessInfo.processInfo.environment
    let roomFolder = URL(fileURLWithPath: env["SALON_ROOM"]!)
    let probe = URL(fileURLWithPath: env["SALON_PROBE"]!)
    let out = URL(fileURLWithPath: env["SALON_OUT"]!)

    let room = try JSONDecoder().decode(
        ScannedRoom.self, from: Data(contentsOf: roomFolder.appendingPathComponent("scan.json")))
    var mesh = tessellate(room, spacing: 0.03)

    struct ProbeFrame: Decodable { let file: String }
    let posesData = try Data(contentsOf: probe.appendingPathComponent("poses.json"))
    let poses = try JSONDecoder().decode([CameraPose].self, from: posesData)
    let files = try JSONDecoder().decode([ProbeFrame].self, from: posesData).map(\.file)
    let empty = DepthMap(width: 0, height: 0, values: [])
    let views = poses.map { ColorView(pose: $0, depth: empty, sharpness: 1) }

    try VertexColorizer.colourize(
        &mesh, views: views,
        loadImage: { try loadRGB(probe.appendingPathComponent(files[$0]), maxPixelSize: 960) },
        progress: { _ in })
    let seen = mesh.colors.filter { $0.w == 255 }.count
    print("salon preview: \(mesh.vertexCount) vertices, \(seen) seen by a photo")
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    try DressedMeshFile.encode(mesh).write(to: out.appendingPathComponent(DressedMeshFile.fileName))
    #expect(seen > mesh.vertexCount / 4)
}

/// Grid of vertices on each wall (normal facing the room) and on the floor.
private func tessellate(_ room: ScannedRoom, spacing: Float) -> DressedMesh {
    var mesh = DressedMesh.empty
    let center = SIMD3(room.floor.center.x, 0, room.floor.center.y)

    func addGrid(origin: SIMD3<Float>, u: SIMD3<Float>, v: SIMD3<Float>, width: Float, height: Float,
                 normal: SIMD3<Float>, faceClass: MeshClass, keep: (SIMD3<Float>) -> Bool = { _ in true }) {
        let nu = max(Int(width / spacing), 1), nv = max(Int(height / spacing), 1)
        let base = UInt32(mesh.positions.count)
        for j in 0...nv {
            for i in 0...nu {
                mesh.positions.append(origin + u * (Float(i) / Float(nu) * width)
                                      + v * (Float(j) / Float(nv) * height))
                mesh.normals.append(normal)
            }
        }
        for j in 0..<nv {
            for i in 0..<nu {
                let a = base + UInt32(j * (nu + 1) + i), row = UInt32(nu + 1)
                let quad = [a, a + 1, a + row + 1, a + row]
                guard keep((quad.map { mesh.positions[Int($0)] }.reduce(.zero, +)) / 4) else { continue }
                mesh.indices += [a, a + 1, a + row, a + 1, a + row + 1, a + row]
                mesh.faceClasses += [faceClass.rawValue, faceClass.rawValue]
            }
        }
    }

    for wall in room.walls {
        let along = SIMD3<Float>(cos(wall.yaw), 0, -sin(wall.yaw))
        var normal = SIMD3<Float>(sin(wall.yaw), 0, cos(wall.yaw))
        if simd_dot(center - wall.center, normal) < 0 { normal = -normal }
        let origin = wall.center - along * (wall.width / 2) - SIMD3(0, wall.height / 2, 0)
        addGrid(origin: origin, u: along, v: [0, 1, 0], width: wall.width, height: wall.height,
                normal: normal, faceClass: .wall)
    }
    let low = room.floor.minimumCorner, high = room.floor.maximumCorner
    addGrid(origin: [low.x, room.floorHeight, low.y], u: [1, 0, 0], v: [0, 0, 1],
            width: high.x - low.x, height: high.y - low.y, normal: [0, 1, 0], faceClass: .floor,
            keep: { room.floor.contains(SIMD2($0.x, $0.z)) && insideWalls($0, room.walls) })
    mesh.colors = [SIMD4<UInt8>](repeating: DressedMesh.unseenColor, count: mesh.vertexCount)
    return mesh
}

/// Ray casting against the wall segments (the scan's walls form the room's outline).
private func insideWalls(_ p: SIMD3<Float>, _ walls: [Wall]) -> Bool {
    var crossings = 0
    for wall in walls {
        let half = SIMD2(cos(wall.yaw), -sin(wall.yaw)) * (wall.width / 2)
        let a = wall.groundPosition - half, b = wall.groundPosition + half
        if (a.y > p.z) != (b.y > p.z), p.x < a.x + (p.z - a.y) * (b.x - a.x) / (b.y - a.y) {
            crossings += 1
        }
    }
    return crossings % 2 == 1
}

private func loadRGB(_ url: URL, maxPixelSize: Int) throws -> RGBImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
          ] as CFDictionary),
          let space = CGColorSpace(name: CGColorSpace.sRGB)
    else { throw CocoaError(.fileReadCorruptFile) }
    let w = image.width, h = image.height
    var rgba = [UInt8](repeating: 0, count: w * h * 4)
    let context = CGContext(data: &rgba, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    var rgb = [UInt8](repeating: 0, count: w * h * 3)
    for i in 0..<(w * h) { rgb[3 * i] = rgba[4 * i]; rgb[3 * i + 1] = rgba[4 * i + 1]; rgb[3 * i + 2] = rgba[4 * i + 2] }
    return RGBImage(width: w, height: h, pixels: rgb)
}
