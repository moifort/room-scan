import Foundation

/// Lecture tabulaire du résultat de la reconnaissance : les meubles regroupés
/// par catégorie et comptés.
public enum FurnitureInventory {
    public struct Group: Identifiable, Hashable, Sendable {
        public let category: FurnitureCategory
        public let pieces: [FurniturePiece]

        public var id: String { category.rawValue }
        public var count: Int { pieces.count }

        /// Vrai si au moins un meuble du groupe a été reconnu sans certitude.
        public var hasUncertainDetection: Bool {
            pieces.contains { !$0.confidence.isCertain }
        }
    }

    public static func groups(for room: ScannedRoom) -> [Group] {
        Dictionary(grouping: room.furniture, by: \.category)
            .map { Group(category: $0.key, pieces: $0.value) }
            .sorted { $0.category.displayName < $1.category.displayName }
    }
}
