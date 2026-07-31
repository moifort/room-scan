import Testing
import simd
import RoomModel
@testable import RoomGeometry

@Test func wallsBetweenTheCameraAndTheRoomAreHidden() throws {
    let room = ScannedRoom.demoLivingRoom
    // Caméra très au sud de la pièce : le mur sud lui fait face et masque l'intérieur.
    let hidden = WallVisibility.hiddenWallIDs(
        walls: room.walls, roomCenter: room.floor.center, cameraPosition: [0, 3, 12])

    let southWall = try #require(room.walls.first { $0.groundPosition.y > 1 })
    let northWall = try #require(room.walls.first { $0.groundPosition.y < -1 })

    #expect(hidden.contains(southWall.id))
    #expect(!hidden.contains(northWall.id))
}

@Test func hidingFollowsTheCameraAroundTheRoom() {
    let room = ScannedRoom.demoLivingRoom
    let fromSouth = WallVisibility.hiddenWallIDs(
        walls: room.walls, roomCenter: room.floor.center, cameraPosition: [0, 3, 12])
    let fromNorth = WallVisibility.hiddenWallIDs(
        walls: room.walls, roomCenter: room.floor.center, cameraPosition: [0, 3, -12])

    #expect(!fromSouth.isEmpty)
    #expect(!fromNorth.isEmpty)
    #expect(fromSouth.isDisjoint(with: fromNorth))
}

@Test func aCameraOverheadHidesNoWall() {
    let room = ScannedRoom.demoLivingRoom
    let hidden = WallVisibility.hiddenWallIDs(
        walls: room.walls, roomCenter: room.floor.center, cameraPosition: [0, 20, 0])

    #expect(hidden.isEmpty)
}
