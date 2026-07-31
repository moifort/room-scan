import Foundation
import Testing
import RoomModel
@testable import RoomStore

private func makeTemporaryStore() throws -> RoomStore {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("roomstore-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return RoomStore(rootDirectory: directory)
}

@Test func savedRoomCanBeListedAndLoadedBack() throws {
    let store = try makeTemporaryStore()
    let metadata = try store.save(.demoLivingRoom, named: "Salon")

    let entries = store.entries()
    #expect(entries.count == 1)
    #expect(entries.first?.metadata.name == "Salon")
    #expect(entries.first?.isReadable == true)

    let loaded = try store.load(id: metadata.id)
    #expect(loaded.furniture.count == ScannedRoom.demoLivingRoom.furniture.count)
    #expect(loaded.walls.count == 4)
}

@Test func savingWritesAThumbnailAlongsideTheScan() throws {
    let store = try makeTemporaryStore()
    let metadata = try store.save(.demoLivingRoom, named: "Salon")

    let entry = try #require(store.entries().first { $0.metadata.id == metadata.id })
    let url = try #require(entry.thumbnailURL)
    #expect(FileManager.default.fileExists(atPath: url.path))
}

@Test func aScanWithoutWallsIsRefused() throws {
    let store = try makeTemporaryStore()
    let empty = ScannedRoom(walls: [], openings: [], furniture: [], floor: FloorOutline(points: []))

    #expect(throws: RoomStoreError.unusableScan) {
        try store.save(empty, named: "Vide")
    }
    #expect(store.entries().isEmpty)
}

@Test func renamingChangesTheNameWithoutTouchingTheScan() throws {
    let store = try makeTemporaryStore()
    let metadata = try store.save(.demoLivingRoom, named: "Salon")
    let scanBefore = try store.load(id: metadata.id)

    try store.rename(id: metadata.id, to: "Séjour")

    #expect(store.entries().first?.metadata.name == "Séjour")
    #expect(try store.load(id: metadata.id) == scanBefore)
}

@Test func deletingRemovesTheRoomEntirely() throws {
    let store = try makeTemporaryStore()
    let metadata = try store.save(.demoLivingRoom, named: "Salon")

    try store.delete(id: metadata.id)
    #expect(store.entries().isEmpty)
    #expect(throws: (any Error).self) { try store.load(id: metadata.id) }
}

@Test func aCorruptedRoomIsListedAsUnreadableWithoutHidingTheOthers() throws {
    let store = try makeTemporaryStore()
    let healthy = try store.save(.demoLivingRoom, named: "Salon")
    let broken = try store.save(.demoLivingRoom, named: "Chambre")

    let scanURL = store.rootDirectory
        .appendingPathComponent(broken.id.uuidString)
        .appendingPathComponent("scan.json")
    try Data("ceci n'est pas du JSON".utf8).write(to: scanURL)

    let entries = store.entries()
    #expect(entries.count == 2)
    #expect(entries.first { $0.metadata.id == healthy.id }?.isReadable == true)
    #expect(entries.first { $0.metadata.id == broken.id }?.isReadable == false)
    #expect(throws: RoomStoreError.unreadable(broken.id)) { try store.load(id: broken.id) }
}

@Test func aFutureSchemaIsRejectedWithAnExplicitError() throws {
    let store = try makeTemporaryStore()
    let metadata = try store.save(.demoLivingRoom, named: "Salon")

    let scanURL = store.rootDirectory
        .appendingPathComponent(metadata.id.uuidString)
        .appendingPathComponent("scan.json")
    var json = try #require(
        try JSONSerialization.jsonObject(with: Data(contentsOf: scanURL)) as? [String: Any])
    json["schemaVersion"] = 99
    try JSONSerialization.data(withJSONObject: json).write(to: scanURL)

    #expect(throws: RoomStoreError.unsupportedSchema(metadata.id, 99)) {
        try store.load(id: metadata.id)
    }
    #expect(store.entries().first?.isReadable == false)
}

@Test func entriesAreSortedMostRecentFirst() throws {
    let store = try makeTemporaryStore()
    _ = try store.save(.demoLivingRoom, named: "Première")
    _ = try store.save(.demoLivingRoom, named: "Seconde")

    let names = store.entries().map(\.metadata.name)
    #expect(names == ["Seconde", "Première"])
}
