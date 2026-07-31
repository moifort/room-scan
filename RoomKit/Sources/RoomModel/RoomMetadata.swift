import Foundation

/// Fiche d'identité d'une pièce enregistrée, indépendante de sa géométrie :
/// renommer une pièce ne touche donc jamais au scan.
public struct RoomMetadata: Identifiable, Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let id: UUID
    public var name: String
    public let createdAt: Date
    public var updatedAt: Date
    public let schemaVersion: Int

    public init(
        id: UUID = UUID(), name: String,
        createdAt: Date = Date(), updatedAt: Date = Date(),
        schemaVersion: Int = RoomMetadata.currentSchemaVersion
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.schemaVersion = schemaVersion
    }
}
