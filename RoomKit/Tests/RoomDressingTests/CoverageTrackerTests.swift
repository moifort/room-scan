import Foundation
import Testing
import simd
@testable import RoomDressing

/// A 1 m × 1 m square in the plane z = 0, centred on the origin, facing `normal`.
private func plane(spacing: Float, normal: SIMD3<Float> = [0, 0, 1], offsetX: Float = 0) -> DressedMesh {
    var mesh = DressedMesh.empty
    let n = Int((1 / spacing).rounded())
    for y in 0...n {
        for x in 0...n {
            mesh.positions.append([Float(x) * spacing - 0.5 + offsetX, Float(y) * spacing - 0.5, 0])
            mesh.normals.append(normal)
        }
    }
    for y in 0..<n {
        for x in 0..<n {
            let i = UInt32(y * (n + 1) + x), row = UInt32(n + 1)
            mesh.indices += [i, i + 1, i + row, i + 1, i + row + 1, i + row]
            mesh.faceClasses += [0, 0]
        }
    }
    mesh.colors = [SIMD4<UInt8>](repeating: DressedMesh.unseenColor, count: mesh.vertexCount)
    return mesh
}

private func merged(_ a: DressedMesh, _ b: DressedMesh) -> DressedMesh {
    var m = a
    let base = UInt32(a.vertexCount)
    m.positions += b.positions
    m.normals += b.normals
    m.colors += b.colors
    m.indices += b.indices.map { $0 + base }
    m.faceClasses += b.faceClasses
    return m
}

private let frontView = ColorView(pose: lookAtPose(eye: [0, 0, 1.5], target: .zero),
                                  depth: noDepth, sharpness: 1)

@Test func unseenMeshIsZeroPercent() {
    #expect(CoverageTracker().fraction(of: plane(spacing: 0.05)) == 0)
    #expect(CoverageTracker().fraction(of: .empty) == 0)
}

@Test func fullyViewedPlaneIsOneHundredPercent() {
    let mesh = plane(spacing: 0.05)
    var tracker = CoverageTracker()
    tracker.markSeen(by: frontView, mesh: mesh)
    #expect(tracker.fraction(of: mesh) > 0.99)
}

@Test func halfViewedPlaneIsAboutFiftyPercent() {
    // Two squares side by side, one facing the camera, one facing away.
    let mesh = merged(plane(spacing: 0.05, offsetX: -0.5),
                      plane(spacing: 0.05, normal: [0, 0, -1], offsetX: 0.5))
    var tracker = CoverageTracker()
    tracker.markSeen(by: ColorView(pose: lookAtPose(eye: [0, 0, 2], target: .zero),
                                   depth: noDepth, sharpness: 1), mesh: mesh)
    #expect(abs(tracker.fraction(of: mesh) - 0.5) < 0.05)
}

@Test func coverageSurvivesMeshRetriangulation() {
    var tracker = CoverageTracker()
    tracker.markSeen(by: frontView, mesh: plane(spacing: 0.02))
    #expect(tracker.fraction(of: plane(spacing: 0.07)) > 0.95)
}
