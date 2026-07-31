import Testing
@testable import RoomModel

@Test func inventoryGroupsPiecesByCategory() {
    let groups = FurnitureInventory.groups(for: .demoLivingRoom)
    let chairs = try? #require(groups.first { $0.category == .chair })

    #expect(chairs?.count == 2)
    #expect(groups.count == 5)
    #expect(groups.map(\.count).reduce(0, +) == ScannedRoom.demoLivingRoom.furniture.count)
}

@Test func inventoryIsSortedByDisplayName() {
    let names = FurnitureInventory.groups(for: .demoLivingRoom).map(\.category.displayName)
    #expect(names == names.sorted())
}

@Test func groupFlagsUncertainDetections() {
    let groups = FurnitureInventory.groups(for: .demoLivingRoom)
    let chairs = groups.first { $0.category == .chair }
    let sofas = groups.first { $0.category == .sofa }

    #expect(chairs?.hasUncertainDetection == true)
    #expect(sofas?.hasUncertainDetection == false)
}

@Test func emptyRoomProducesEmptyInventory() {
    let room = ScannedRoom(walls: [], openings: [], furniture: [], floor: FloorOutline(points: []))
    #expect(FurnitureInventory.groups(for: room).isEmpty)
}
