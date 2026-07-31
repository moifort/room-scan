import Foundation
import RoomModel
import simd

/// Désignation d'un meuble à partir d'un point touché à l'écran.
///
/// Le ciblage d'entités de RealityKit ne remonte aucun événement dans une scène
/// non-AR pilotée par une caméra virtuelle. On lance donc le rayon soi-même :
/// la caméra et les boîtes des meubles sont entièrement connues, le calcul est
/// pur, et il se teste sans écran ni simulateur.
public enum FurniturePicking {
    /// Rayon partant de l'œil et traversant le point touché.
    public static func ray(
        at point: SIMD2<Float>, viewSize: SIMD2<Float>,
        camera: OrbitCamera, verticalFieldOfView: Float
    ) -> (origin: SIMD3<Float>, direction: SIMD3<Float>) {
        let eye = camera.position
        let forward = simd_normalize(camera.target - eye)
        let worldUp = SIMD3<Float>(0, 1, 0)

        // Quand la caméra vise presque à la verticale, l'axe « droite » calculé
        // depuis la verticale du monde dégénère ; on repart d'un autre axe.
        var right = simd_cross(forward, worldUp)
        if simd_length(right) < 0.001 {
            right = simd_cross(forward, SIMD3<Float>(0, 0, 1))
        }
        right = simd_normalize(right)
        let up = simd_normalize(simd_cross(right, forward))

        let width = max(viewSize.x, 1)
        let height = max(viewSize.y, 1)
        let aspect = width / height
        let tanHalf = tan(verticalFieldOfView / 2)

        let ndcX = 2 * point.x / width - 1
        let ndcY = 1 - 2 * point.y / height

        let direction = simd_normalize(
            right * (ndcX * tanHalf * aspect) + up * (ndcY * tanHalf) + forward)
        return (eye, direction)
    }

    /// Identifiant du meuble touché, le plus proche de l'œil s'il y en a
    /// plusieurs sur le trajet du rayon.
    public static func pick(
        at point: SIMD2<Float>, viewSize: SIMD2<Float>,
        camera: OrbitCamera, verticalFieldOfView: Float,
        furniture: [FurniturePiece]
    ) -> UUID? {
        let ray = ray(
            at: point, viewSize: viewSize, camera: camera,
            verticalFieldOfView: verticalFieldOfView)

        var closest: (id: UUID, distance: Float)?
        for piece in furniture {
            guard let distance = intersection(
                origin: ray.origin, direction: ray.direction, piece: piece)
            else { continue }

            if closest == nil || distance < closest!.distance {
                closest = (piece.id, distance)
            }
        }
        return closest?.id
    }

    /// Distance à laquelle le rayon entre dans la boîte du meuble, ou `nil`.
    static func intersection(
        origin: SIMD3<Float>, direction: SIMD3<Float>, piece: FurniturePiece
    ) -> Float? {
        // La boîte est posée au sol : son centre est à mi-hauteur.
        let center = SIMD3(piece.center.x, piece.height / 2, piece.center.z)
        let half = SIMD3(piece.footprint.x / 2, piece.height / 2, piece.footprint.y / 2)

        // Ramener le rayon dans le repère du meuble annule sa rotation, ce qui
        // réduit le test à celui d'une boîte alignée sur les axes.
        let rotation = simd_quatf(angle: -piece.yaw, axis: [0, 1, 0])
        let localOrigin = rotation.act(origin - center)
        let localDirection = rotation.act(direction)

        var near = -Float.greatestFiniteMagnitude
        var far = Float.greatestFiniteMagnitude

        for axis in 0..<3 {
            let originComponent = localOrigin[axis]
            let directionComponent = localDirection[axis]
            let halfComponent = half[axis]

            if abs(directionComponent) < 1e-6 {
                // Rayon parallèle à cette paire de faces : il doit déjà être
                // entre les deux, sinon il ne touchera jamais.
                if abs(originComponent) > halfComponent { return nil }
                continue
            }
            let inverse = 1 / directionComponent
            var t1 = (-halfComponent - originComponent) * inverse
            var t2 = (halfComponent - originComponent) * inverse
            if t1 > t2 { swap(&t1, &t2) }

            near = max(near, t1)
            far = min(far, t2)
            if near > far { return nil }
        }
        return far < 0 ? nil : max(near, 0)
    }
}
