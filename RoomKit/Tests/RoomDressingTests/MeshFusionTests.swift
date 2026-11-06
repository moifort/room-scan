import Foundation
import RoomModel
import Testing
import simd
@testable import RoomDressing

extension MeshPiece {
    static func unitTriangle(at offset: SIMD3<Float>, rotationY: Float = 0,
                             faceClass: MeshClass = .none) -> MeshPiece {
        var transform = simd_float4x4(simd_quatf(angle: rotationY, axis: [0, 1, 0]))
        transform.columns.3 = SIMD4(offset, 1)
        return MeshPiece(
            localPositions: [[0, 0, 0], [1, 0, 0], [0, 1, 0]],
            localNormals: [[0, 0, 1], [0, 0, 1], [0, 0, 1]],
            indices: [0, 1, 2], faceClasses: [faceClass.rawValue], transform: transform)
    }
}

private func close(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Bool { simd_length(a - b) < 1e-5 }

@Test func fuseEmptyGivesEmptyMesh() {
    #expect(MeshFusion.fuse([]) == .empty)
}

@Test func fuseAppliesTransformAndOffsetsIndices() {
    let mesh = MeshFusion.fuse([.unitTriangle(at: .zero), .unitTriangle(at: [2, 0, 0])])
    #expect(mesh.vertexCount == 6)
    #expect(mesh.indices == [0, 1, 2, 3, 4, 5])
    #expect(close(mesh.positions[3], [2, 0, 0]))
    #expect(close(mesh.positions[4], [3, 0, 0]))
    #expect(mesh.colors.allSatisfy { $0 == DressedMesh.unseenColor })
    #expect(mesh.faceClasses.count == 2)
}

@Test func fuseRotatesNormals() {
    let mesh = MeshFusion.fuse([.unitTriangle(at: .zero, rotationY: .pi / 2)])
    #expect(close(mesh.normals[0], [1, 0, 0]))
}

/// A grid of wall-classified triangles lying in the plane z = `depth`.
private func wallGrid(depth: Float) -> DressedMesh {
    var pieces: [MeshPiece] = []
    for x in stride(from: Float(-1.5), through: 1.5, by: 0.5) {
        for y in stride(from: Float(0.2), through: 2.2, by: 0.5) {
            pieces.append(.unitTriangle(at: [x, y, depth], faceClass: .wall))
        }
    }
    // Keep the triangles small so they stay within the wall's extent.
    var mesh = MeshFusion.fuse(pieces)
    for i in mesh.positions.indices {
        let corner = i % 3
        if corner == 1 { mesh.positions[i].x -= 0.9 }
        if corner == 2 { mesh.positions[i].y -= 0.9 }
    }
    return mesh
}

@Test func wallPointsThreeCentimetresOffGiveThreeCentimetres() throws {
    let wall = Wall(center: [0, 1.3, 0], width: 4, height: 2.6, yaw: 0)
    let distance = try #require(WallAlignment.medianDistance(of: wallGrid(depth: 0.03), to: [wall]))
    #expect(abs(distance - 0.03) < 0.001)
}

@Test func meshWithoutWallFacesGivesNil() {
    let wall = Wall(center: [0, 1.3, 0], width: 4, height: 2.6, yaw: 0)
    let mesh = MeshFusion.fuse([.unitTriangle(at: .zero, faceClass: .floor)])
    #expect(WallAlignment.medianDistance(of: mesh, to: [wall]) == nil)
}

@Test func pointsBeyondTheWallEndAreIgnored() {
    let wall = Wall(center: [0, 1.3, 0], width: 1, height: 2.6, yaw: 0)
    let mesh = MeshFusion.fuse([.unitTriangle(at: [5, 1, 0.03], faceClass: .wall)])
    #expect(WallAlignment.medianDistance(of: mesh, to: [wall]) == nil)
}
