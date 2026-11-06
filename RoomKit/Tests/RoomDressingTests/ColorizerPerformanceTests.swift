import Foundation
import Testing
import simd
@testable import RoomDressing

/// Room-sized workload: 200 000 vertices, 200 photos. Opt-in, in release:
/// `PERF=1 swift test -c release --filter colourizingARoomTakesUnderAMinute`.
@Test(.enabled(if: ProcessInfo.processInfo.environment["PERF"] != nil))
func colourizingARoomTakesUnderAMinute() throws {
    var mesh = DressedMesh.empty
    let side = 447  // ≈ 200 000 vertices on a 4.5 m wall
    for y in 0..<side {
        for x in 0..<side {
            mesh.positions.append([Float(x) * 0.01 - 2.2, Float(y) * 0.006, 0])
            mesh.normals.append([0, 0, 1])
        }
    }
    for y in 0..<(side - 1) {
        for x in 0..<(side - 1) {
            let i = UInt32(y * side + x)
            mesh.indices += [i, i + 1, i + UInt32(side)]
            mesh.faceClasses.append(MeshClass.wall.rawValue)
        }
    }
    mesh.colors = [SIMD4<UInt8>](repeating: DressedMesh.unseenColor, count: mesh.vertexCount)

    let views = (0..<200).map { i in
        ColorView(pose: lookAtPose(eye: [Float(i % 20) * 0.2 - 2, 1.4, 2], target: [0, 1.4, 0]),
                  depth: noDepth, sharpness: 1)
    }
    let image = RGBImage.solid(width: 960, height: 720, color: [120, 80, 40])
    let start = Date()
    try VertexColorizer.colourize(&mesh, views: views, loadImage: { _ in image }, progress: { _ in })
    let elapsed = Date().timeIntervalSince(start)
    print("colourize: \(mesh.vertexCount) vertices × \(views.count) views in \(elapsed) s")
    #expect(elapsed < 60)
}
