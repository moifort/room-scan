import Foundation
import simd

/// Caméra tournant autour d'un point de visée. Purement géométrique : aucune
/// dépendance au moteur de rendu, ce qui la rend testable sans écran.
public struct OrbitCamera: Equatable, Sendable {
    /// Rester au-dessus du sol évite de voir la maquette par en dessous.
    public static let minElevation: Float = 0.08
    /// Rester en deçà du zénith évite le renversement de l'image au pôle.
    public static let maxElevation: Float = .pi / 2 - 0.02
    public static let minDistance: Float = 0.6
    public static let maxDistance: Float = 40

    public private(set) var target: SIMD3<Float>
    public private(set) var distance: Float
    public private(set) var azimuth: Float
    public private(set) var elevation: Float

    public init(target: SIMD3<Float>, distance: Float, azimuth: Float, elevation: Float) {
        self.target = target
        self.distance = OrbitCamera.clampDistance(distance)
        self.azimuth = OrbitCamera.wrapAngle(azimuth)
        self.elevation = OrbitCamera.clampElevation(elevation)
    }

    /// Position de l'œil, en coordonnées monde.
    public var position: SIMD3<Float> {
        let horizontal = distance * cos(elevation)
        return target + SIMD3(
            horizontal * sin(azimuth),
            distance * sin(elevation),
            horizontal * cos(azimuth))
    }

    public mutating func orbit(deltaAzimuth: Float, deltaElevation: Float) {
        azimuth = OrbitCamera.wrapAngle(azimuth + deltaAzimuth)
        elevation = OrbitCamera.clampElevation(elevation + deltaElevation)
    }

    public mutating func zoom(factor: Float) {
        guard factor > 0, factor.isFinite else { return }
        distance = OrbitCamera.clampDistance(distance * factor)
    }

    /// Déplace le point de visée dans le plan du sol, selon l'orientation
    /// courante de la caméra : « à droite » reste à droite de l'écran.
    public mutating func pan(right: Float, forward: Float) {
        let rightAxis = SIMD3<Float>(cos(azimuth), 0, -sin(azimuth))
        let forwardAxis = SIMD3<Float>(-sin(azimuth), 0, -cos(azimuth))
        target += rightAxis * right + forwardAxis * forward
    }

    public mutating func topDown() {
        elevation = OrbitCamera.maxElevation
    }

    public mutating func recenter(on target: SIMD3<Float>, distance: Float) {
        self.target = target
        self.distance = OrbitCamera.clampDistance(distance)
    }

    private static func clampElevation(_ value: Float) -> Float {
        min(max(value, minElevation), maxElevation)
    }

    private static func clampDistance(_ value: Float) -> Float {
        min(max(value, minDistance), maxDistance)
    }

    private static func wrapAngle(_ value: Float) -> Float {
        var angle = value.truncatingRemainder(dividingBy: 2 * .pi)
        if angle > .pi { angle -= 2 * .pi }
        if angle < -.pi { angle += 2 * .pi }
        return angle
    }
}
