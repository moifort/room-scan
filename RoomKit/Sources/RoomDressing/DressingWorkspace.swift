import Foundation

/// Temporary folder of one dressing pass: photos, depth maps, manifest and,
/// once computed, the realistic mesh. Moved into the room folder on save,
/// discarded otherwise.
public struct DressingWorkspace: Equatable, Sendable {
    public let root: URL

    public static func create(in parent: URL) throws -> DressingWorkspace {
        let root = parent.appendingPathComponent("dressing-\(UUID().uuidString)", isDirectory: true)
        let workspace = DressingWorkspace(root: root)
        for folder in [workspace.photosDirectory, workspace.depthDirectory] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return workspace
    }

    public init(root: URL) {
        self.root = root
    }

    public var photosDirectory: URL { root.appendingPathComponent("photos", isDirectory: true) }
    public var depthDirectory: URL { root.appendingPathComponent("depth", isDirectory: true) }
    public var manifestURL: URL { root.appendingPathComponent(KeyframeManifest.fileName) }
    public var meshURL: URL { root.appendingPathComponent(DressedMeshFile.fileName) }

    public func url(for relativePath: String) -> URL {
        root.appendingPathComponent(relativePath)
    }

    public func readManifest() throws -> KeyframeManifest {
        try JSONDecoder().decode(KeyframeManifest.self, from: Data(contentsOf: manifestURL))
    }

    public func write(_ manifest: KeyframeManifest) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
    }

    public func discard() {
        try? FileManager.default.removeItem(at: root)
    }
}
