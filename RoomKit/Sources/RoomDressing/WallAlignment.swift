import Foundation
import RoomModel
import simd

/// Measures how well the ARKit mesh sits on the walls RoomPlan found: the two
/// come from separate passes, and the realistic view is only trustworthy if
/// they share one coordinate frame.
public enum WallAlignment {
    static let extentTolerance: Float = 0.10

    /// Median distance from wall-classified mesh vertices to the vertical
    /// plane of the nearest scanned wall, or nil when no such vertex lies
    /// within a wall's extent.
    public static func medianDistance(of mesh: DressedMesh, to walls: [Wall]) -> Float? {
        guard !walls.isEmpty else { return nil }
        var wallVertices = Set<Int>()
        for t in 0..<mesh.triangleCount where mesh.faceClasses[t] == MeshClass.wall.rawValue {
            let (a, b, c) = mesh.triangle(t)
            wallVertices.formUnion([a, b, c])
        }

        var distances: [Float] = []
        distances.reserveCapacity(wallVertices.count)
        for v in wallVertices {
            let p = mesh.positions[v]
            var best: Float?
            for wall in walls {
                let normal = SIMD3<Float>(sin(wall.yaw), 0, cos(wall.yaw))
                let along = SIMD3<Float>(cos(wall.yaw), 0, -sin(wall.yaw))
                let offset = p - wall.center
                guard abs(simd_dot(offset, along)) <= wall.width / 2 + extentTolerance,
                      abs(offset.y) <= wall.height / 2 + extentTolerance
                else { continue }
                let distance = abs(simd_dot(offset, normal))
                best = min(best ?? .infinity, distance)
            }
            if let best { distances.append(best) }
        }
        guard !distances.isEmpty else { return nil }
        distances.sort()
        let mid = distances.count / 2
        return distances.count.isMultiple(of: 2)
            ? (distances[mid - 1] + distances[mid]) / 2 : distances[mid]
    }
}
