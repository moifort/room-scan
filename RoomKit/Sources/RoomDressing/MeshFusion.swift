import Foundation
import simd

/// One ARKit mesh anchor, copied out of ARKit's buffers.
public struct MeshPiece: Sendable {
    public var localPositions: [SIMD3<Float>]
    public var localNormals: [SIMD3<Float>]
    public var indices: [UInt32]
    public var faceClasses: [UInt8]
    /// Anchor → world.
    public var transform: simd_float4x4

    public init(
        localPositions: [SIMD3<Float>], localNormals: [SIMD3<Float>], indices: [UInt32],
        faceClasses: [UInt8], transform: simd_float4x4
    ) {
        self.localPositions = localPositions
        self.localNormals = localNormals
        self.indices = indices
        self.faceClasses = faceClasses
        self.transform = transform
    }
}

public enum MeshFusion {
    /// Merges the pieces into one world-space mesh, not yet coloured.
    public static func fuse(_ pieces: [MeshPiece]) -> DressedMesh {
        var mesh = DressedMesh.empty
        let vertexTotal = pieces.reduce(0) { $0 + $1.localPositions.count }
        mesh.positions.reserveCapacity(vertexTotal)
        mesh.normals.reserveCapacity(vertexTotal)

        for piece in pieces {
            let base = UInt32(mesh.positions.count)
            let t = piece.transform
            let rotation = simd_float3x3(
                SIMD3(t.columns.0.x, t.columns.0.y, t.columns.0.z),
                SIMD3(t.columns.1.x, t.columns.1.y, t.columns.1.z),
                SIMD3(t.columns.2.x, t.columns.2.y, t.columns.2.z))
            for p in piece.localPositions {
                let world = t * SIMD4(p, 1)
                mesh.positions.append(SIMD3(world.x, world.y, world.z))
            }
            for n in piece.localNormals {
                let rotated = rotation * n
                let length = simd_length(rotated)
                mesh.normals.append(length > 0 ? rotated / length : .zero)
            }
            mesh.indices += piece.indices.map { $0 + base }
            let triangles = piece.indices.count / 3
            mesh.faceClasses += piece.faceClasses.count == triangles
                ? piece.faceClasses : [UInt8](repeating: MeshClass.none.rawValue, count: triangles)
        }
        mesh.colors = [SIMD4<UInt8>](repeating: DressedMesh.unseenColor, count: mesh.positions.count)
        return mesh
    }
}
