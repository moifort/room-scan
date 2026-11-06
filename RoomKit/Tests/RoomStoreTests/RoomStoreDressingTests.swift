import Foundation
import RoomDressing
import RoomModel
import Testing
@testable import RoomStore

private func temporaryDirectory(_ prefix: String) throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A finished dressing workspace: mesh, one photo, its depth, the manifest.
private func finishedWorkspace(withMesh: Bool = true) throws -> DressingWorkspace {
    let workspace = try DressingWorkspace.create(in: temporaryDirectory("dressing"))
    try Data([0xFF, 0xD8]).write(to: workspace.url(for: "photos/000.jpg"))
    try Data([1, 2]).write(to: workspace.url(for: "depth/000.f16"))
    try workspace.write(KeyframeManifest())
    if withMesh {
        try DressedMeshFile.encode(.demoCube(size: 1)).write(to: workspace.meshURL)
    }
    return workspace
}

@Test func savingWithDressingCopiesMeshAndPhotosButNotDepth() throws {
    let store = RoomStore(rootDirectory: try temporaryDirectory("store"))
    let metadata = try store.save(.demoLivingRoom, named: "Salon", dressing: try finishedWorkspace())

    let folder = store.rootDirectory.appendingPathComponent(metadata.id.uuidString)
    let fm = FileManager.default
    #expect(fm.fileExists(atPath: folder.appendingPathComponent("photos/000.jpg").path))
    #expect(fm.fileExists(atPath: folder.appendingPathComponent("photos.json").path))
    #expect(!fm.fileExists(atPath: folder.appendingPathComponent("depth").path))
    let meshURL = try #require(store.realisticMeshURL(for: metadata.id))
    #expect(try DressedMeshFile.decode(Data(contentsOf: meshURL)) == .demoCube(size: 1))
}

@Test func realisticMeshURLIsNilWithoutDressing() throws {
    let store = RoomStore(rootDirectory: try temporaryDirectory("store"))
    let metadata = try store.save(.demoLivingRoom, named: "Salon")
    #expect(store.realisticMeshURL(for: metadata.id) == nil)
}

@Test func failedDressingCopyLeavesNoFolder() throws {
    let store = RoomStore(rootDirectory: try temporaryDirectory("store"))
    #expect(throws: RoomStoreError.self) {
        try store.save(.demoLivingRoom, named: "Salon", dressing: try finishedWorkspace(withMesh: false))
    }
    #expect(store.entries().isEmpty)
}
