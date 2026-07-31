import Foundation
import simd

extension ScannedRoom {
    /// Salon de 4,2 × 3,4 m servant d'aperçu et de jeu d'essai tant qu'aucun
    /// scan réel n'est disponible — la capture exige un appareil à LiDAR.
    public static let demoLivingRoom: ScannedRoom = {
        let width: Float = 4.2
        let depth: Float = 3.4
        let ceiling: Float = 2.5
        let halfWidth = width / 2
        let halfDepth = depth / 2

        let walls = [
            Wall(center: [0, ceiling / 2, -halfDepth], width: width, height: ceiling, yaw: 0),
            Wall(center: [0, ceiling / 2, halfDepth], width: width, height: ceiling, yaw: .pi),
            Wall(center: [-halfWidth, ceiling / 2, 0], width: depth, height: ceiling, yaw: -.pi / 2),
            Wall(center: [halfWidth, ceiling / 2, 0], width: depth, height: ceiling, yaw: .pi / 2),
        ]

        let openings = [
            Opening(kind: .door, center: [-1.2, 1.05, halfDepth], width: 0.85, height: 2.1, yaw: .pi),
            Opening(kind: .window, center: [0.6, 1.4, -halfDepth], width: 1.4, height: 1.2, yaw: 0),
        ]

        let furniture = [
            FurniturePiece(
                category: .sofa, center: [-1.1, 0.4, 0.9],
                footprint: [2.1, 0.95], height: 0.8, yaw: 0, confidence: .high),
            FurniturePiece(
                category: .table, center: [-1.0, 0.22, -0.1],
                footprint: [1.1, 0.6], height: 0.45, yaw: 0, confidence: .high),
            FurniturePiece(
                category: .television, center: [-1.1, 0.9, -1.55],
                footprint: [1.2, 0.08], height: 0.7, yaw: 0, confidence: .medium),
            FurniturePiece(
                category: .storage, center: [1.6, 0.9, -0.4],
                footprint: [0.9, 0.45], height: 1.8, yaw: .pi / 2, confidence: .high),
            FurniturePiece(
                category: .chair, center: [1.2, 0.45, 1.1],
                footprint: [0.5, 0.5], height: 0.9, yaw: 0.6, confidence: .medium),
            FurniturePiece(
                category: .chair, center: [1.75, 0.45, 1.3],
                footprint: [0.5, 0.5], height: 0.9, yaw: -0.4, confidence: .low),
        ]

        return ScannedRoom(
            walls: walls, openings: openings, furniture: furniture,
            floor: FloorOutline(points: [
                [-halfWidth, -halfDepth], [halfWidth, -halfDepth],
                [halfWidth, halfDepth], [-halfWidth, halfDepth],
            ]))
    }()
}
