import Foundation
import Testing
import simd
@testable import RoomModel

@Test func scannedRoomSurvivesAJSONRoundTrip() throws {
    let original = ScannedRoom.demoLivingRoom
    let data = try JSONEncoder().encode(original)
    let restored = try JSONDecoder().decode(ScannedRoom.self, from: data)

    #expect(restored.walls.count == original.walls.count)
    #expect(restored.furniture.count == original.furniture.count)
    #expect(restored.openings.count == original.openings.count)
    #expect(restored.floor.points == original.floor.points)
    #expect(restored.furniture.first?.category == original.furniture.first?.category)
    #expect(restored.furniture.first?.center == original.furniture.first?.center)
}

@Test func demoRoomIsAPlausibleLivingRoom() {
    let room = ScannedRoom.demoLivingRoom
    #expect(room.walls.count == 4)
    #expect(room.furniture.count == 6)
    #expect(room.openings.contains { $0.kind == .door })
    #expect(room.openings.contains { $0.kind == .window })
    #expect(room.furniture.allSatisfy { $0.height > 0 && $0.footprint.x > 0 && $0.footprint.y > 0 })
}

@Test func demoRoomFurnitureFitsInsideTheFloor() {
    let room = ScannedRoom.demoLivingRoom
    let halfSize = room.floor.size / 2
    let center = room.floor.center

    // Un meuble qui traverse un mur trahirait une donnée d'exemple bâclée, et
    // ferait douter du rendu plutôt que de la donnée.
    for piece in room.furniture {
        let halfWidth = piece.footprint.x / 2
        let halfDepth = piece.footprint.y / 2
        // Emprise de la boîte orientée, projetée sur chaque axe.
        let reach = SIMD2(
            abs(halfWidth * cos(piece.yaw)) + abs(halfDepth * sin(piece.yaw)),
            abs(halfWidth * sin(piece.yaw)) + abs(halfDepth * cos(piece.yaw)))
        let offset = simd_abs(piece.groundPosition - center)

        #expect(offset.x + reach.x <= halfSize.x + 0.02)
        #expect(offset.y + reach.y <= halfSize.y + 0.02)
    }
}

@Test func absurdDimensionsAreClampedRatherThanStored() {
    let piece = FurniturePiece(
        category: .chair, center: [0, 0.4, 0],
        footprint: [0, 900], height: -3, yaw: 0, confidence: .low)

    #expect(piece.footprint.x >= FurniturePiece.minimumDimension)
    #expect(piece.footprint.y <= FurniturePiece.maximumDimension)
    #expect(piece.height >= FurniturePiece.minimumDimension)
}

@Test func floorOutlineDerivesCenterAndRadiusFromItsPoints() {
    let floor = FloorOutline(points: [[-2, -1], [2, -1], [2, 1], [-2, 1]])
    #expect(floor.center == SIMD2<Float>(0, 0))
    #expect(floor.size == SIMD2<Float>(4, 2))
    #expect(abs(floor.boundingRadius - sqrt(5)) < 0.001)
}

@Test func floorOutlineFallsBackToWallBounds() {
    let room = ScannedRoom.demoLivingRoom
    let fallback = FloorOutline(boundingWalls: room.walls)
    #expect(fallback.size.x > 3)
    #expect(fallback.size.y > 2)
}

@Test func onlyHighConfidenceCountsAsCertain() {
    #expect(DetectionConfidence.high.isCertain)
    #expect(!DetectionConfidence.medium.isCertain)
    #expect(!DetectionConfidence.low.isCertain)
}
