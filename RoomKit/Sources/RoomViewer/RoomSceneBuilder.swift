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

    private let selectionMarker = ModelEntity()

    private static let wallThickness: Float = 0.06

    public init(room: ScannedRoom) {
        self.room = room
    }

    /// Construit la scène. Avec un modèle exporté par le scanner, c'est lui qui
    /// est affiché — murs épais, ouvertures découpées, meubles reconnaissables.
    /// Sans modèle, on retombe sur des volumes reconstruits depuis les mesures.
    public func buildScene(modelURL: URL? = nil) async -> Entity {
        let root = Entity()

        if let modelURL, let model = try? await Entity(contentsOf: modelURL) {
            root.addChild(model)
            indexWalls(in: model)
        } else {
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
        }

        root.addChild(makeSelectionMarker())
        root.addChild(makeLighting())
        return root
    }

    /// Retrouve les murs du modèle exporté pour pouvoir les masquer quand ils
    /// passent devant la caméra. Les noms viennent du scanner : si la
    /// convention change, on ne masque rien plutôt que de masquer au hasard.
    private func indexWalls(in model: Entity) {
        var byIdentifier: [UUID: Entity] = [:]
        var remaining = room.walls

        func visit(_ entity: Entity) {
            let name = entity.name.lowercased()
            if name.contains("wall"), !remaining.isEmpty {
                // Rapprocher chaque entité du mur mesuré le plus proche.
                let position = entity.position(relativeTo: nil)
                let ground = SIMD2(position.x, position.z)
                let nearest = remaining.min {
                    simd_distance($0.groundPosition, ground)
                        < simd_distance($1.groundPosition, ground)
                }
                if let nearest {
                    byIdentifier[nearest.id] = entity
                    remaining.removeAll { $0.id == nearest.id }
                }
            }
            for child in entity.children { visit(child) }
        }

        visit(model)
        wallEntities = byIdentifier
    }

    /// Signale le meuble sélectionné. Une cage translucide posée autour de lui
    /// plutôt qu'un changement de couleur : le modèle du scanner est un bloc
    /// dont on ne connaît pas la structure interne, mais dont on connaît
    /// exactement l'encombrement de chaque meuble.
    public func setHighlight(_ isHighlighted: Bool, forFurniture id: UUID) {
        guard isHighlighted, let piece = room.furniture.first(where: { $0.id == id }) else {
            selectionMarker.isEnabled = false
            return
        }

        selectionMarker.model?.mesh = .generateBox(
            width: piece.footprint.x + 0.04,
            height: piece.height + 0.04,
            depth: piece.footprint.y + 0.04,
            cornerRadius: 0.02)
        selectionMarker.position = [piece.center.x, piece.height / 2, piece.center.z]
        selectionMarker.orientation = simd_quatf(angle: piece.yaw, axis: [0, 1, 0])
        selectionMarker.isEnabled = true

        // Teinter aussi le volume quand c'est nous qui l'avons construit.
        if let entity = furnitureEntities[id] as? ModelEntity {
            entity.model?.materials = [SimpleMaterial(
                color: FurniturePalette.color(for: piece.category).lightened(by: 0.35),
                isMetallic: false)]
        }
    }

    private func makeSelectionMarker() -> Entity {
        selectionMarker.model = ModelComponent(
            mesh: .generateBox(size: 0.01),
            materials: [selectionMaterial])
        selectionMarker.isEnabled = false
        selectionMarker.name = "selection"
        return selectionMarker
    }

    private var selectionMaterial: SimpleMaterial {
        var material = SimpleMaterial()
        material.color = .init(tint: UIColor.systemBlue.withAlphaComponent(0.35))
        material.metallic = 0
        material.roughness = 1
        return material
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
