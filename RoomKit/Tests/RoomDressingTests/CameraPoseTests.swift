import Foundation
import Testing
import simd
@testable import RoomDressing

extension CameraPose {
    /// Identity camera, 1920×1440 image, f = 1000.
    static let sample = CameraPose(
        transform: matrix_identity_float4x4,
        intrinsics: simd_float3x3(SIMD3(1000, 0, 0), SIMD3(0, 1000, 0), SIMD3(960, 720, 1)),
        resolution: SIMD2(1920, 1440))
}

@Test func projectsPointStraightAheadToPrincipalPoint() throws {
    let hit = try #require(CameraPose.sample.project([0, 0, -2]))
    #expect(hit.pixel == [960, 720])
    #expect(hit.depth == 2)
}

@Test func pointAboveCentreProjectsAbove() throws {
    let hit = try #require(CameraPose.sample.project([0, 0.5, -2]))
    #expect(hit.pixel.y == 470)
}

@Test func pointToTheRightProjectsRight() throws {
    let hit = try #require(CameraPose.sample.project([0.5, 0, -2]))
    #expect(hit.pixel.x == 1210)
}

@Test func pointBehindCameraDoesNotProject() {
    #expect(CameraPose.sample.project([0, 0, 2]) == nil)
}

@Test func halfScaleHalvesIntrinsics() throws {
    let half = CameraPose.sample.scaled(by: 0.5)
    #expect(half.resolution == [960, 720])
    let hit = try #require(half.project([0.5, 0, -2]))
    #expect(hit.pixel.x == 605)
}

@Test func poseDecodesProbeJSON() throws {
    let json = """
    {"transform":[1,0,0,0, 0,1,0,0, 0,0,1,0, 0.5,1.2,-3,1],
     "intrinsics":[1330,0,0, 0,1330,0, 958,722,1], "resolution":[1920,1440]}
    """
    let pose = try JSONDecoder().decode(CameraPose.self, from: Data(json.utf8))
    #expect(pose.position == [0.5, 1.2, -3])
    #expect(pose.intrinsics.columns.2.x == 958)
    let again = try JSONDecoder().decode(CameraPose.self, from: JSONEncoder().encode(pose))
    #expect(again == pose)
}

@Test func depthRoundTripsWithinHalfPrecision() throws {
    let values = stride(from: Float(0.5), through: 4, by: 0.25).map { $0 }
    let map = DepthMap(width: values.count, height: 1, values: values)
    let decoded = try DepthMapFile.decode(DepthMapFile.encode(map))
    for (a, b) in zip(values, decoded.values) { #expect(abs(a - b) < 0.002) }
}

@Test func zeroDepthReadsAsNil() {
    let map = DepthMap(width: 2, height: 1, values: [0, 1.5])
    #expect(map.depth(atPixel: [10, 10], imageResolution: [1920, 1440]) == nil)
    #expect(map.depth(atPixel: [1500, 10], imageResolution: [1920, 1440]) == 1.5)
}

@Test func checkerboardIsSharperThanFlatGrey() {
    let size = 32
    let flat = [UInt8](repeating: 128, count: size * size)
    let checker = (0..<(size * size)).map { i in UInt8(((i % size) + (i / size)) % 2 == 0 ? 0 : 255) }
    #expect(Sharpness.varianceOfLaplacian(luma: checker, width: size, height: size)
            > Sharpness.varianceOfLaplacian(luma: flat, width: size, height: size))
    #expect(Sharpness.varianceOfLaplacian(luma: flat, width: size, height: size) == 0)
}

@Test func discardRemovesWorkspace() throws {
    let parent = URL(fileURLWithPath: NSTemporaryDirectory())
    let workspace = try DressingWorkspace.create(in: parent)
    #expect(FileManager.default.fileExists(atPath: workspace.photosDirectory.path))
    try workspace.write(KeyframeManifest(keyframes: [
        KeyframeRecord(file: "photos/000.jpg", depthFile: "depth/000.f16", pose: .sample,
                       timestamp: 1, sharpness: 2)]))
    #expect(try workspace.readManifest().keyframes.count == 1)
    workspace.discard()
    #expect(!FileManager.default.fileExists(atPath: workspace.root.path))
}
