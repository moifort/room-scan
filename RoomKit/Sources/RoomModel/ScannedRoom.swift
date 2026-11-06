import Foundation

/// Résultat d'un scan. Traité comme immuable : rien ne le réécrit une fois
/// enregistré, ce qui garantit que les mesures d'origine restent intactes.
public struct ScannedRoom: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let walls: [Wall]
    public let openings: [Opening]
    public let furniture: [FurniturePiece]
    public let floor: FloorOutline

    public init(
        schemaVersion: Int = ScannedRoom.currentSchemaVersion,
        walls: [Wall], openings: [Opening],
        furniture: [FurniturePiece], floor: FloorOutline
    ) {
        self.schemaVersion = schemaVersion
        self.walls = walls
        self.openings = openings
        self.furniture = furniture
        self.floor = floor.isEmpty ? FloorOutline(boundingWalls: walls) : floor
    }

    /// Un scan sans mur n'est pas exploitable : la pièce n'a pas de forme.
    public var isUsable: Bool { !walls.isEmpty }

    /// Hauteur sous plafond estimée, à partir du mur le plus haut.
    public var ceilingHeight: Float { walls.map(\.height).max() ?? 2.5 }

    /// Altitude du sol dans le repère du scan : la base moyenne des murs.
    public var floorHeight: Float {
        guard !walls.isEmpty else { return 0 }
        return walls.map { $0.center.y - $0.height / 2 }.reduce(0, +) / Float(walls.count)
    }
}
