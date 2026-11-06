import Foundation
import simd

/// The real-shape mesh of a room, in world coordinates (metres), coloured per
/// vertex from the dressing photos.
///
/// `colors.w` tells whether a photo saw the vertex: 255 when coloured from a
/// photo, 0 when no photo saw it.
public struct DressedMesh: Equatable, Sendable {
    public var positions: [SIMD3<Float>]
    public var normals: [SIMD3<Float>]
    public var colors: [SIMD4<UInt8>]
    /// Three indices per triangle.
    public var indices: [UInt32]
    /// ARKit `ARMeshClassification` raw value, one per triangle.
    public var faceClasses: [UInt8]

    public static let unseenColor = SIMD4<UInt8>(128, 128, 128, 0)
    public static let empty = DressedMesh(
        positions: [], normals: [], colors: [], indices: [], faceClasses: [])

    public init(
        positions: [SIMD3<Float>], normals: [SIMD3<Float>], colors: [SIMD4<UInt8>],
        indices: [UInt32], faceClasses: [UInt8]
    ) {
        self.positions = positions
        self.normals = normals
        self.colors = colors
        self.indices = indices
        self.faceClasses = faceClasses
    }

    public var vertexCount: Int { positions.count }
    public var triangleCount: Int { indices.count / 3 }
    public var isEmpty: Bool { positions.isEmpty || indices.isEmpty }

    /// The three vertex indices of a triangle.
    public func triangle(_ t: Int) -> (Int, Int, Int) {
        (Int(indices[3 * t]), Int(indices[3 * t + 1]), Int(indices[3 * t + 2]))
    }

    public func centroid(ofTriangle t: Int) -> SIMD3<Float> {
        let (a, b, c) = triangle(t)
        return (positions[a] + positions[b] + positions[c]) / 3
    }

    public func area(ofTriangle t: Int) -> Float {
        let (a, b, c) = triangle(t)
        return simd_length(simd_cross(positions[b] - positions[a], positions[c] - positions[a])) / 2
    }

    /// Geometric normal of a triangle (unit length, or zero when degenerate).
    public func normal(ofTriangle t: Int) -> SIMD3<Float> {
        let (a, b, c) = triangle(t)
        let n = simd_cross(positions[b] - positions[a], positions[c] - positions[a])
        let length = simd_length(n)
        return length > 0 ? n / length : .zero
    }
}

/// ARKit mesh classification values carried by `DressedMesh.faceClasses`.
public enum MeshClass: UInt8, Sendable {
    case none = 0, wall, floor, ceiling, table, seat, window, door
}
