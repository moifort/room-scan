import Foundation
import simd

/// Un mur, décrit par son centre, ses dimensions et son orientation au sol.
public struct Wall: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let center: SIMD3<Float>
    public let width: Float
    public let height: Float
    /// Rotation autour de l'axe vertical, en radians.
    public let yaw: Float

    public init(
        id: UUID = UUID(), center: SIMD3<Float>,
        width: Float, height: Float, yaw: Float
    ) {
        self.id = id
        self.center = center
        self.width = max(width, 0.01)
        self.height = max(height, 0.01)
        self.yaw = yaw
    }

    /// Normale horizontale du mur, dans le plan du sol.
    public var normal: SIMD2<Float> { SIMD2(sin(yaw), cos(yaw)) }

    /// Position du mur projetée au sol.
    public var groundPosition: SIMD2<Float> { SIMD2(center.x, center.z) }
}
