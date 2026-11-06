import Foundation
import Testing
import simd
@testable import RoomDressing

/// A camera at `eye` looking at `target`, 64×48 image, f = 60.
func lookAtPose(eye: SIMD3<Float>, target: SIMD3<Float>) -> CameraPose {
    let z = simd_normalize(eye - target)  // camera looks down −Z
    let up: SIMD3<Float> = abs(z.y) > 0.9 ? [0, 0, -1] : [0, 1, 0]
    let x = simd_normalize(simd_cross(up, z))
    let y = simd_cross(z, x)
    let transform = simd_float4x4(SIMD4(x, 0), SIMD4(y, 0), SIMD4(z, 0), SIMD4(eye, 1))
    return CameraPose(
        transform: transform,
        intrinsics: simd_float3x3(SIMD3(60, 0, 0), SIMD3(0, 60, 0), SIMD3(32, 24, 1)),
        resolution: SIMD2(64, 48))
}

let noDepth = DepthMap(width: 4, height: 3, values: [Float](repeating: 0, count: 12))

private let faceNormals: [SIMD3<Float>] = [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]]
private let faceColours: [SIMD3<UInt8>] = [
    [200, 10, 10], [10, 200, 10], [10, 10, 200], [200, 200, 10], [10, 200, 200], [200, 10, 200]]

@Test func cubeFacesGetTheirCameraColours() throws {
    var mesh = DressedMesh.demoCube(size: 1)
    let views = faceNormals.map {
        ColorView(pose: lookAtPose(eye: $0 * 2, target: .zero), depth: noDepth, sharpness: 1)
    }
    let images = faceColours.map { RGBImage.solid(width: 64, height: 48, color: $0) }
    try VertexColorizer.colourize(&mesh, views: views, loadImage: { images[$0] }, progress: { _ in })

    for v in 0..<mesh.vertexCount {
        let face = faceNormals.firstIndex(of: mesh.normals[v])!
        let c = mesh.colors[v]
        #expect(c.w == 255)
        #expect(SIMD3(c.x, c.y, c.z) == faceColours[face])
    }
}

@Test func halfSizeImagesAreSampledAtScale() throws {
    var mesh = DressedMesh.demoCube(size: 1)
    let view = ColorView(pose: lookAtPose(eye: [2, 0, 0], target: .zero), depth: noDepth, sharpness: 1)
    // Left half black, right half white, at half resolution (32×24).
    var pixels = [UInt8]()
    for _ in 0..<24 { for x in 0..<32 { pixels += [UInt8](repeating: x < 16 ? 0 : 255, count: 3) } }
    try VertexColorizer.colourize(&mesh, views: [view],
                                  loadImage: { _ in RGBImage(width: 32, height: 24, pixels: pixels) },
                                  progress: { _ in })
    // On the +X face seen from +X, world −Z is on the image's right (bright).
    for v in 0..<mesh.vertexCount where mesh.normals[v] == [1, 0, 0] {
        #expect(mesh.colors[v].x == (mesh.positions[v].z < 0 ? 255 : 0))
    }
}

@Test func occludedVertexIgnoresTheView() {
    let pose = lookAtPose(eye: [0, 0, 2], target: .zero)
    // The photo's depth says something sits 1 m away, in front of the point at 2 m.
    let blocked = DepthMap(width: 4, height: 3, values: [Float](repeating: 1, count: 12))
    let view = ColorView(pose: pose, depth: blocked, sharpness: 1)
    #expect(Visibility.weight(of: .zero, normal: [0, 0, 1], in: view) == nil)
    let clear = ColorView(pose: pose, depth: DepthMap(width: 4, height: 3,
                                                      values: [Float](repeating: 2, count: 12)),
                          sharpness: 1)
    #expect(Visibility.weight(of: .zero, normal: [0, 0, 1], in: clear) != nil)
}

@Test func grazingAngleIsRejected() {
    let view = ColorView(pose: lookAtPose(eye: [0, 0, 2], target: .zero), depth: noDepth, sharpness: 1)
    let tilted = SIMD3<Float>(sin(70 * .pi / 180), 0, cos(70 * .pi / 180))
    #expect(Visibility.weight(of: .zero, normal: tilted, in: view) == nil)
}

@Test func tooFarIsRejected() {
    let view = ColorView(pose: lookAtPose(eye: [0, 0, 3.5], target: .zero), depth: noDepth, sharpness: 1)
    #expect(Visibility.weight(of: .zero, normal: [0, 0, 1], in: view) == nil)
}

@Test func sharperViewWins() throws {
    var mesh = DressedMesh.demoCube(size: 1)
    let pose = lookAtPose(eye: [0, 0, 2], target: .zero)
    let views = [ColorView(pose: pose, depth: noDepth, sharpness: 4),
                 ColorView(pose: pose, depth: noDepth, sharpness: 1)]
    let images = [RGBImage.solid(width: 64, height: 48, color: [255, 0, 0]),
                  RGBImage.solid(width: 64, height: 48, color: [0, 0, 255])]
    try VertexColorizer.colourize(&mesh, views: views, loadImage: { images[$0] }, progress: { _ in })
    let front = mesh.colors[mesh.normals.firstIndex(of: [0, 0, 1])!]
    #expect(front.x > 190)
    #expect(front.z < 65)
}

@Test func colourizeWithoutViewsLeavesEverythingUnseen() throws {
    var mesh = DressedMesh.demoCube(size: 1)
    var reached: Double = 0
    try VertexColorizer.colourize(&mesh, views: [], loadImage: { _ in fatalError() },
                                  progress: { reached = $0 })
    #expect(mesh.colors.allSatisfy { $0 == DressedMesh.unseenColor })
    #expect(reached == 1)
}

@Test func unseenVertexBorrowsNeighbourColour() {
    // Two triangles sharing an edge; vertex 3 only belongs to the second.
    var mesh = DressedMesh(
        positions: [[0, 0, 0], [1, 0, 0], [0, 1, 0], [1, 1, 0]],
        normals: [[0, 0, 1], [0, 0, 1], [0, 0, 1], [0, 0, 1]],
        colors: [[100, 0, 0, 255], [100, 0, 0, 255], [100, 0, 0, 255], DressedMesh.unseenColor],
        indices: [0, 1, 2, 1, 3, 2], faceClasses: [0, 0])
    VertexColorizer.fillUnseen(&mesh, seen: [true, true, true, false])
    #expect(mesh.colors[3] == SIMD4(100, 0, 0, 0))
}

@Test func progressReachesOne() throws {
    var mesh = DressedMesh.demoCube(size: 1)
    let views = (0..<4).map { _ in
        ColorView(pose: lookAtPose(eye: [0, 0, 2], target: .zero), depth: noDepth, sharpness: 1)
    }
    var steps: [Double] = []
    try VertexColorizer.colourize(
        &mesh, views: views,
        loadImage: { _ in .solid(width: 64, height: 48, color: [1, 2, 3]) },
        progress: { steps.append($0) })
    #expect(steps == [0.25, 0.5, 0.75, 1])
}
