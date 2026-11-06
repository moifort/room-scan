import Foundation
import simd

/// Share of the room's surface already seen by a sharp dressing photo.
///
/// Coverage is remembered per 5 cm cell of space rather than per triangle:
/// ARKit keeps re-triangulating its mesh while the user walks around, and a
/// cell survives that where a triangle index would not. Each accepted photo
/// marks its cells once; reading the fraction only looks cells up.
public struct CoverageTracker: Sendable {
    public static let cellSize: Float = 0.05

    private var covered = Set<SIMD3<Int32>>()

    public init() {}

    public var coveredCellCount: Int { covered.count }

    public mutating func markSeen(by view: ColorView, mesh: DressedMesh) {
        for t in 0..<mesh.triangleCount {
            let centroid = mesh.centroid(ofTriangle: t)
            let key = Self.cell(of: centroid)
            guard !covered.contains(key) else { continue }
            if Visibility.hit(point: centroid, normal: Self.normal(ofTriangle: t, in: mesh), in: view) != nil {
                covered.insert(key)
            }
        }
    }

    /// Covered area over total area, 0 for an empty mesh.
    public func fraction(of mesh: DressedMesh) -> Float {
        var total: Float = 0
        var seen: Float = 0
        for t in 0..<mesh.triangleCount {
            let area = mesh.area(ofTriangle: t)
            total += area
            if isCovered(triangle: t, in: mesh) { seen += area }
        }
        return total > 0 ? seen / total : 0
    }

    public func isCovered(triangle t: Int, in mesh: DressedMesh) -> Bool {
        covered.contains(Self.cell(of: mesh.centroid(ofTriangle: t)))
    }

    static func cell(of p: SIMD3<Float>) -> SIMD3<Int32> {
        SIMD3<Int32>((p / cellSize).rounded(.down))
    }

    /// ARKit's own vertex normals, averaged: they face outward, while the
    /// winding of the triangles is not guaranteed to.
    static func normal(ofTriangle t: Int, in mesh: DressedMesh) -> SIMD3<Float> {
        let (a, b, c) = mesh.triangle(t)
        let sum = mesh.normals[a] + mesh.normals[b] + mesh.normals[c]
        let length = simd_length(sum)
        return length > 0 ? sum / length : mesh.normal(ofTriangle: t)
    }
}
