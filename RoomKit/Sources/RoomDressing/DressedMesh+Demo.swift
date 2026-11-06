import Foundation
import simd

extension DressedMesh {
    /// A cube centred on the origin whose six faces carry pure, distinct
    /// colours: lets the realistic viewer be checked without a scan.
    public static func demoCube(size: Float) -> DressedMesh {
        let h = size / 2
        // (normal, u axis, v axis, colour) for each face.
        let faces: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>, SIMD4<UInt8>)] = [
            ([1, 0, 0], [0, 0, -1], [0, 1, 0], [230, 40, 40, 255]),
            ([-1, 0, 0], [0, 0, 1], [0, 1, 0], [40, 200, 70, 255]),
            ([0, 1, 0], [1, 0, 0], [0, 0, -1], [40, 90, 230, 255]),
            ([0, -1, 0], [1, 0, 0], [0, 0, 1], [235, 210, 40, 255]),
            ([0, 0, 1], [1, 0, 0], [0, 1, 0], [40, 210, 220, 255]),
            ([0, 0, -1], [-1, 0, 0], [0, 1, 0], [210, 50, 200, 255]),
        ]
        var mesh = DressedMesh.empty
        for (normal, u, v, color) in faces {
            let base = UInt32(mesh.positions.count)
            for (su, sv) in [(-1, -1), (1, -1), (1, 1), (-1, 1)] as [(Float, Float)] {
                mesh.positions.append(normal * h + u * (su * h) + v * (sv * h))
                mesh.normals.append(normal)
                mesh.colors.append(color)
            }
            mesh.indices += [base, base + 1, base + 2, base, base + 2, base + 3]
            mesh.faceClasses += [MeshClass.none.rawValue, MeshClass.none.rawValue]
        }
        return mesh
    }

    /// Axis-aligned bounds of the vertices, or nil for an empty mesh.
    public var bounds: (min: SIMD3<Float>, max: SIMD3<Float>)? {
        guard var low = positions.first else { return nil }
        var high = low
        for p in positions {
            low = simd_min(low, p)
            high = simd_max(high, p)
        }
        return (low, high)
    }
}
