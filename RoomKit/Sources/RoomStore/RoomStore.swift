import Foundation
import RoomDressing
import RoomModel

/// Une pièce telle qu'elle apparaît dans la bibliothèque, sans charger sa
/// géométrie complète.
public struct RoomEntry: Identifiable, Hashable, Sendable {
    public let metadata: RoomMetadata
    public let thumbnailURL: URL?
    /// Faux si les fichiers sont corrompus ou d'une version inconnue : la pièce
    /// reste visible et supprimable, mais ne s'ouvre pas.
    public let isReadable: Bool

    public var id: UUID { metadata.id }
}

/// Bibliothèque locale : un dossier par pièce, contenant `room.json`,
/// `scan.json` et `thumbnail.png`.
public struct RoomStore: Sendable {
    public let rootDirectory: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public static func documentsStore() throws -> RoomStore {
        let documents = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        let root = documents.appendingPathComponent("Rooms", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return RoomStore(rootDirectory: root)
    }

    // MARK: - Écriture

    /// `modelURL` est le modèle exporté par le scanner. Optionnel : une pièce
    /// sans modèle reste consultable via la maquette reconstruite.
    /// `dressing` apporte la vue réaliste : maillage coloré, photos et leur
    /// manifeste sont copiés, les cartes de profondeur non.
    @discardableResult
    public func save(
        _ room: ScannedRoom, named name: String, modelURL: URL? = nil,
        dressing: DressingWorkspace? = nil
    ) throws -> RoomMetadata {
        guard room.isUsable else { throw RoomStoreError.unusableScan }

        let metadata = RoomMetadata(name: name)
        let folder = directory(for: metadata.id)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try encoder.encode(room).write(to: folder.appendingPathComponent("scan.json"))
            try encoder.encode(metadata).write(to: folder.appendingPathComponent("room.json"))
            let thumbnail = try ThumbnailRenderer.pngData(for: room)
            try thumbnail.write(to: folder.appendingPathComponent("thumbnail.png"))

            if let modelURL {
                try FileManager.default.copyItem(
                    at: modelURL, to: folder.appendingPathComponent(RoomStore.modelFileName))
            }
            if let dressing {
                try copyDressing(dressing, into: folder)
            }
        } catch {
            // Ne pas laisser un dossier à moitié écrit derrière soi.
            try? FileManager.default.removeItem(at: folder)
            throw RoomStoreError.writeFailed(error.localizedDescription)
        }
        return metadata
    }

    public func rename(id: UUID, to name: String) throws {
        let url = directory(for: id).appendingPathComponent("room.json")
        guard var metadata = try? decoder.decode(RoomMetadata.self, from: Data(contentsOf: url))
        else { throw RoomStoreError.unreadable(id) }

        metadata.name = name
        metadata.updatedAt = Date()
        do {
            try encoder.encode(metadata).write(to: url)
        } catch {
            throw RoomStoreError.writeFailed(error.localizedDescription)
        }
    }

    public func delete(id: UUID) throws {
        try FileManager.default.removeItem(at: directory(for: id))
    }

    // MARK: - Lecture

    public func entries() -> [RoomEntry] {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: rootDirectory, includingPropertiesForKeys: nil)) ?? []

        return folders.compactMap(entry(atFolder:))
            .sorted {
                // Ordre total : à date égale, l'identifiant tranche, pour que
                // la liste ne change pas d'ordre d'un affichage à l'autre.
                ($0.metadata.createdAt, $0.id.uuidString)
                    > ($1.metadata.createdAt, $1.id.uuidString)
            }
    }

    public func load(id: UUID) throws -> ScannedRoom {
        let url = directory(for: id).appendingPathComponent("scan.json")
        guard let data = try? Data(contentsOf: url) else {
            throw RoomStoreError.unreadable(id)
        }
        if let version = schemaVersion(in: data), version > ScannedRoom.currentSchemaVersion {
            throw RoomStoreError.unsupportedSchema(id, version)
        }
        guard let room = try? decoder.decode(ScannedRoom.self, from: data) else {
            throw RoomStoreError.unreadable(id)
        }
        return room
    }

    /// Modèle 3D de la pièce, s'il a été enregistré avec elle.
    public func modelURL(for id: UUID) -> URL? {
        let url = directory(for: id).appendingPathComponent(RoomStore.modelFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Maillage réaliste de la pièce, si elle a été habillée.
    public func realisticMeshURL(for id: UUID) -> URL? {
        let url = directory(for: id).appendingPathComponent(DressedMeshFile.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Détails

    private func copyDressing(_ dressing: DressingWorkspace, into folder: URL) throws {
        let fm = FileManager.default
        try fm.copyItem(at: dressing.meshURL,
                        to: folder.appendingPathComponent(DressedMeshFile.fileName))
        try fm.copyItem(at: dressing.photosDirectory,
                        to: folder.appendingPathComponent("photos", isDirectory: true))
        try fm.copyItem(at: dressing.manifestURL,
                        to: folder.appendingPathComponent(KeyframeManifest.fileName))
        let log = dressing.root.appendingPathComponent("dressing.log")
        if fm.fileExists(atPath: log.path) {
            try fm.copyItem(at: log, to: folder.appendingPathComponent("dressing.log"))
        }
    }

    static let modelFileName = "model.usdz"

    private func directory(for id: UUID) -> URL {
        rootDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func entry(atFolder folder: URL) -> RoomEntry? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("room.json")),
              let metadata = try? decoder.decode(RoomMetadata.self, from: data)
        else { return nil }

        let thumbnail = folder.appendingPathComponent("thumbnail.png")
        let readable = (try? load(id: metadata.id)) != nil

        return RoomEntry(
            metadata: metadata,
            thumbnailURL: FileManager.default.fileExists(atPath: thumbnail.path) ? thumbnail : nil,
            isReadable: readable)
    }

    /// Lit la seule version du schéma sans décoder le reste : un fichier écrit
    /// par une version future doit produire un message clair, pas une erreur de
    /// décodage obscure.
    private func schemaVersion(in data: Data) -> Int? {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["schemaVersion"] as? Int
    }

    /// ISO 8601 **avec** les fractions de seconde. La variante standard tronque
    /// à la seconde : deux pièces enregistrées coup sur coup deviendraient
    /// indiscernables et la bibliothèque afficherait un ordre arbitraire.
    private func makeDateFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private var encoder: JSONEncoder {
        let formatter = makeDateFormatter()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }

    private var decoder: JSONDecoder {
        let formatter = makeDateFormatter()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = formatter.date(from: text) else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: decoder.codingPath,
                        debugDescription: "Date illisible : \(text)"))
            }
            return date
        }
        return decoder
    }
}
