#if os(iOS)
import Foundation
import RealityKit
import RoomModel
import UIKit
import simd

/// Traduit une pièce scannée en entités RealityKit. Conserve les entités par
/// identifiant pour que la sélection et le masquage des murs puissent les
/// retrouver sans reparcourir la scène.
@MainActor
public final class RoomSceneBuilder {
    public let room: ScannedRoom
    public private(set) var wallEntities: [UUID: Entity] = [:]
    public private(set) var furnitureEntities: [UUID: Entity] = [:]

    private static let wallThickness: Float = 0.06

    public init(room: ScannedRoom) {
        self.room = room
    }

    public func buildScene() -> Entity {
        let root = Entity()
        root.addChild(makeFloor())
        for wall in room.walls {
            let entity = makeWall(wall)
            wallEntities[wall.id] = entity
            root.addChild(entity)
        }
        for opening in room.openings {
            root.addChild(makeOpening(opening))
        }
        for piece in room.furniture {
            let entity = makeFurniture(piece)
            furnitureEntities[piece.id] = entity
            root.addChild(entity)
        }
        root.addChild(makeLighting())
        return root
    }

    /// Éclaircit le meuble sélectionné plutôt que de changer sa couleur : la
    /// catégorie reste lisible pendant la sélection.
    public func setHighlight(_ isHighlighted: Bool, forFurniture id: UUID) {
        guard let entity = furnitureEntities[id] as? ModelEntity,
              let piece = room.furniture.first(where: { $0.id == id })
        else { return }

        let base = FurniturePalette.color(for: piece.category)
        let color = isHighlighted ? base.lightened(by: 0.35) : base
        entity.model?.materials = [SimpleMaterial(color: color, isMetallic: false)]
    }

    // MARK: - Éléments

    private func makeFloor() -> Entity {
        let size = room.floor.size
        let entity = ModelEntity(
            mesh: .generateBox(width: max(size.x, 0.5), height: 0.02, depth: max(size.y, 0.5)),
            materials: [SimpleMaterial(
                color: UIColor(white: 0.88, alpha: 1), isMetallic: false)])
        entity.position = [room.floor.center.x, -0.01, room.floor.center.y]
        entity.name = "floor"

        // Le sol est une cible tactile pour que « toucher à côté d'un meuble »
        // soit un événement reçu, et non l'absence d'événement : c'est ce qui
        // permet de désélectionner sans second geste concurrent.
        entity.generateCollisionShapes(recursive: false)
        entity.components.set(InputTargetComponent())
        return entity
    }

    private func makeWall(_ wall: Wall) -> Entity {
        let entity = ModelEntity(
            mesh: .generateBox(
                width: wall.width, height: wall.height, depth: RoomSceneBuilder.wallThickness),
            materials: [SimpleMaterial(
                color: UIColor(white: 0.96, alpha: 1), isMetallic: false)])
        entity.position = wall.center
        entity.orientation = simd_quatf(angle: wall.yaw, axis: [0, 1, 0])
        entity.name = "wall:\(wall.id.uuidString)"
        return entity
    }

    private func makeOpening(_ opening: Opening) -> Entity {
        let color: UIColor = switch opening.kind {
        case .door: UIColor(red: 0.55, green: 0.42, blue: 0.32, alpha: 1)
        case .window: UIColor(red: 0.60, green: 0.80, blue: 0.92, alpha: 1)
        case .opening: UIColor(white: 0.75, alpha: 1)
        }
        // Légèrement plus épais que le mur pour éviter le clignotement de
        // profondeur entre deux surfaces coplanaires.
        let entity = ModelEntity(
            mesh: .generateBox(
                width: opening.width, height: opening.height,
                depth: RoomSceneBuilder.wallThickness * 1.4),
            materials: [SimpleMaterial(color: color, isMetallic: false)])
        entity.position = opening.center
        entity.orientation = simd_quatf(angle: opening.yaw, axis: [0, 1, 0])
        entity.name = "opening:\(opening.id.uuidString)"
        return entity
    }

    private func makeFurniture(_ piece: FurniturePiece) -> Entity {
        let mesh = MeshResource.generateBox(
            width: piece.footprint.x, height: piece.height, depth: piece.footprint.y,
            cornerRadius: 0.01)
        let entity = ModelEntity(
            mesh: mesh,
            materials: [SimpleMaterial(
                color: FurniturePalette.color(for: piece.category), isMetallic: false)])
        // Le centre mesuré est celui du volume ; poser la base au sol.
        entity.position = [piece.center.x, piece.height / 2, piece.center.z]
        entity.orientation = simd_quatf(angle: piece.yaw, axis: [0, 1, 0])
        entity.name = "furniture:\(piece.id.uuidString)"

        // Nécessaire pour que le tap atteigne l'entité.
        entity.generateCollisionShapes(recursive: false)
        entity.components.set(InputTargetComponent())
        return entity
    }

    /// Une scène RealityKit non-AR n'a aucun éclairage par défaut : sans cette
    /// lumière, la maquette est entièrement noire.
    private func makeLighting() -> Entity {
        let light = DirectionalLight()
        light.light.intensity = 3200
        light.light.color = .white
        light.look(at: .zero, from: [3, 6, 4], relativeTo: nil)

        let fill = DirectionalLight()
        fill.light.intensity = 1200
        fill.look(at: .zero, from: [-4, 3, -3], relativeTo: nil)

        let holder = Entity()
        holder.addChild(light)
        holder.addChild(fill)
        holder.name = "lighting"
        return holder
    }
}

extension UIColor {
    /// Éclaircit une couleur en la rapprochant du blanc.
    func lightened(by amount: CGFloat) -> UIColor {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return self }
        return UIColor(
            red: red + (1 - red) * amount,
            green: green + (1 - green) * amount,
            blue: blue + (1 - blue) * amount,
            alpha: alpha)
    }
}
#endif
