import Foundation
import simd

/// Emprise au sol de la pièce. Sert au cadrage de la caméra et à la vignette.
public struct FloorOutline: Codable, Hashable, Sendable {
    public let points: [SIMD2<Float>]

    public init(points: [SIMD2<Float>]) {
        self.points = points
    }

    /// Repli utilisé quand le scanner ne fournit pas de polygone de sol :
    /// le rectangle englobant des murs.
    public init(boundingWalls walls: [Wall]) {
        guard !walls.isEmpty else {
            self.init(points: [])
            return
        }
        var minimum = SIMD2<Float>(repeating: .greatestFiniteMagnitude)
        var maximum = SIMD2<Float>(repeating: -.greatestFiniteMagnitude)
        for wall in walls {
            // Les deux extrémités du mur, obtenues en suivant sa direction.
            let direction = SIMD2(cos(wall.yaw), -sin(wall.yaw)) * (wall.width / 2)
            for end in [wall.groundPosition + direction, wall.groundPosition - direction] {
                minimum = simd_min(minimum, end)
                maximum = simd_max(maximum, end)
            }
        }
        self.init(points: [
            minimum, SIMD2(maximum.x, minimum.y), maximum, SIMD2(minimum.x, maximum.y),
        ])
    }

    public var isEmpty: Bool { points.isEmpty }

    public var center: SIMD2<Float> {
        guard !points.isEmpty else { return .zero }
        return (minimumCorner + maximumCorner) / 2
    }

    public var size: SIMD2<Float> {
        guard !points.isEmpty else { return .zero }
        return maximumCorner - minimumCorner
    }

    /// Rayon du cercle englobant, utilisé pour cadrer la caméra sur la pièce.
    public var boundingRadius: Float {
        guard !points.isEmpty else { return 1 }
        return simd_length(size) / 2
    }

    private var minimumCorner: SIMD2<Float> {
        points.reduce(SIMD2(repeating: .greatestFiniteMagnitude), simd_min)
    }

    private var maximumCorner: SIMD2<Float> {
        points.reduce(SIMD2(repeating: -.greatestFiniteMagnitude), simd_max)
    }
}
