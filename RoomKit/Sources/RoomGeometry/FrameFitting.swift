import Foundation
import simd
import RoomModel

/// Calcule la distance de recul nécessaire pour que la pièce entière tienne
/// dans le cadre, et la position de départ de la caméra.
public enum FrameFitting {
    /// Marge autour de la pièce, pour ne pas coller aux bords de l'écran.
    /// Vue de biais, la pièce est plus large que son grand côté : cette marge
    /// absorbe l'écart sans reculer jusqu'à la rendre minuscule.
    public static let margin: Float = 1.32

    public static func distance(
        boundingRadius: Float, verticalFieldOfView: Float, aspectRatio: Float
    ) -> Float {
        let halfVertical = verticalFieldOfView / 2
        // Sur un écran plus étroit que haut, c'est l'horizontale qui contraint.
        let halfHorizontal = atan(tan(halfVertical) * max(aspectRatio, 0.01))
        let limiting = min(halfVertical, halfHorizontal)
        return boundingRadius * margin / max(tan(limiting), 0.01)
    }

    public static func initialCamera(
        for room: ScannedRoom, verticalFieldOfView: Float, aspectRatio: Float
    ) -> OrbitCamera {
        let floorCenter = room.floor.center
        // Le demi-grand côté, et non la demi-diagonale : vue de biais, la
        // diagonale ne se projette jamais entièrement à l'écran, et cadrer
        // dessus laisse la maquette perdue au milieu du vide.
        let radius = max(room.floor.size.max() / 2, 1)
        return OrbitCamera(
            target: SIMD3(floorCenter.x, room.ceilingHeight / 3, floorCenter.y),
            distance: distance(
                boundingRadius: radius,
                verticalFieldOfView: verticalFieldOfView,
                aspectRatio: aspectRatio),
            azimuth: .pi / 5,
            elevation: .pi / 5)
    }
}
