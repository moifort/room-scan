import Foundation

/// Catégorie d'un meuble reconnu. Les cas connus reprennent le vocabulaire de
/// RoomPlan ; `unknown` conserve telle quelle une catégorie inconnue de cette
/// version de l'app plutôt que de la perdre.
public enum FurnitureCategory: Hashable, Sendable {
    case storage, refrigerator, stove, bed, sink, washerDryer, toilet, bathtub
    case oven, dishwasher, table, sofa, chair, fireplace, television, stairs
    case unknown(String)

    public static let knownCases: [FurnitureCategory] = [
        .storage, .refrigerator, .stove, .bed, .sink, .washerDryer, .toilet, .bathtub,
        .oven, .dishwasher, .table, .sofa, .chair, .fireplace, .television, .stairs,
    ]

    public var displayName: String {
        switch self {
        case .storage: "Rangement"
        case .refrigerator: "Réfrigérateur"
        case .stove: "Cuisinière"
        case .bed: "Lit"
        case .sink: "Évier"
        case .washerDryer: "Lave-linge"
        case .toilet: "WC"
        case .bathtub: "Baignoire"
        case .oven: "Four"
        case .dishwasher: "Lave-vaisselle"
        case .table: "Table"
        case .sofa: "Canapé"
        case .chair: "Chaise"
        case .fireplace: "Cheminée"
        case .television: "Télévision"
        case .stairs: "Escalier"
        case .unknown: "Meuble"
        }
    }
}

extension FurnitureCategory: RawRepresentable {
    public init(rawValue: String) {
        self = FurnitureCategory.knownCases.first { $0.rawValue == rawValue }
            ?? .unknown(rawValue)
    }

    public var rawValue: String {
        switch self {
        case .storage: "storage"
        case .refrigerator: "refrigerator"
        case .stove: "stove"
        case .bed: "bed"
        case .sink: "sink"
        case .washerDryer: "washerDryer"
        case .toilet: "toilet"
        case .bathtub: "bathtub"
        case .oven: "oven"
        case .dishwasher: "dishwasher"
        case .table: "table"
        case .sofa: "sofa"
        case .chair: "chair"
        case .fireplace: "fireplace"
        case .television: "television"
        case .stairs: "stairs"
        case .unknown(let raw): raw
        }
    }
}

extension FurnitureCategory: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = FurnitureCategory(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
