import Foundation
import simd
import RoomModel

/// Détermine quels murs masquer pour qu'on voie l'intérieur de la maquette.
///
/// Un mur situé entre la caméra et le centre de la pièce cache tout ce qu'il y
/// a derrière lui. On le repère sans normale ni orientation : il suffit que la
/// caméra se trouve du côté extérieur du mur.
public enum WallVisibility {
    /// En deçà de cette hauteur d'observation, la question ne se pose plus :
    /// vue du dessus, aucun mur ne gêne.
    public static let overheadThreshold: Float = 0.9

    public static func hiddenWallIDs(
        walls: [Wall], roomCenter: SIMD2<Float>, cameraPosition: SIMD3<Float>
    ) -> Set<UUID> {
        let camera = SIMD2(cameraPosition.x, cameraPosition.z)
        let horizontalDistance = simd_length(camera - roomCenter)

        // Caméra quasiment à la verticale : on regarde par le plafond ouvert.
        guard horizontalDistance > 0.01,
              cameraPosition.y / max(horizontalDistance, 0.01) < 1 / overheadThreshold
        else { return [] }

        return Set(
            walls.filter { wall in
                let outward = wall.groundPosition - roomCenter
                let toCamera = camera - wall.groundPosition
                return simd_dot(outward, toCamera) > 0
            }.map(\.id))
    }
}
