#if os(iOS)
import Foundation
import RoomGeometry
import RoomModel
import RoomPlan
import simd

/// Traduit le résultat de RoomPlan vers le modèle de l'app. C'est la frontière :
/// au-delà, plus rien ne connaît RoomPlan.
public enum CapturedRoomTranslator {
    public static func translate(_ captured: CapturedRoom) -> ScannedRoom {
        let walls = captured.walls.map { surface in
            Wall(
                center: TransformReading.position(of: surface.transform),
                width: surface.dimensions.x,
                height: surface.dimensions.y,
                yaw: TransformReading.yaw(of: surface.transform))
        }

        let openings =
            captured.doors.map { translate($0, as: .door) }
            + captured.windows.map { translate($0, as: .window) }
            + captured.openings.map { translate($0, as: .opening) }

        let furniture = captured.objects.map { object in
            FurniturePiece(
                category: category(of: object.category),
                center: TransformReading.position(of: object.transform),
                // RoomPlan donne largeur, hauteur puis profondeur.
                footprint: SIMD2(object.dimensions.x, object.dimensions.z),
                height: object.dimensions.y,
                yaw: TransformReading.yaw(of: object.transform),
                confidence: confidence(of: object.confidence))
        }

        return ScannedRoom(
            walls: walls, openings: openings, furniture: furniture,
            floor: floorOutline(of: captured, walls: walls))
    }

    // MARK: - Éléments

    private static func translate(
        _ surface: CapturedRoom.Surface, as kind: OpeningKind
    ) -> Opening {
        Opening(
            kind: kind,
            center: TransformReading.position(of: surface.transform),
            width: surface.dimensions.x,
            height: surface.dimensions.y,
            yaw: TransformReading.yaw(of: surface.transform))
    }

    /// RoomPlan fournit une surface de sol ; quand elle manque, on retombe sur
    /// le rectangle englobant des murs.
    private static func floorOutline(
        of captured: CapturedRoom, walls: [Wall]
    ) -> FloorOutline {
        guard let floor = captured.floors.first else {
            return FloorOutline(boundingWalls: walls)
        }
        let center = TransformReading.position(of: floor.transform)
        let angle = TransformReading.yaw(of: floor.transform)
        let halfWidth = floor.dimensions.x / 2
        let halfDepth = floor.dimensions.y / 2

        let corners: [SIMD2<Float>] = [
            [-halfWidth, -halfDepth], [halfWidth, -halfDepth],
            [halfWidth, halfDepth], [-halfWidth, halfDepth],
        ]
        return FloorOutline(points: corners.map { corner in
            SIMD2(
                center.x + corner.x * cos(angle) - corner.y * sin(angle),
                center.z + corner.x * sin(angle) + corner.y * cos(angle))
        })
    }

    private static func category(
        of category: CapturedRoom.Object.Category
    ) -> FurnitureCategory {
        switch category {
        case .storage: .storage
        case .refrigerator: .refrigerator
        case .stove: .stove
        case .bed: .bed
        case .sink: .sink
        case .washerDryer: .washerDryer
        case .toilet: .toilet
        case .bathtub: .bathtub
        case .oven: .oven
        case .dishwasher: .dishwasher
        case .table: .table
        case .sofa: .sofa
        case .chair: .chair
        case .fireplace: .fireplace
        case .television: .television
        case .stairs: .stairs
        @unknown default: .unknown(String(describing: category))
        }
    }

    private static func confidence(
        of confidence: CapturedRoom.Confidence
    ) -> DetectionConfidence {
        switch confidence {
        case .high: .high
        case .medium: .medium
        case .low: .low
        @unknown default: .low
        }
    }
}
#endif
