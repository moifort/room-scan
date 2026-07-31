import Foundation
import simd

/// Un meuble reconnu : sa catégorie, son encombrement mesuré et sa pose au sol.
public struct FurniturePiece: Identifiable, Codable, Hashable, Sendable {
    /// Un scan rend parfois des dimensions nulles ou absurdes. Les borner ici
    /// évite qu'un seul objet mal mesuré ne casse le rendu ou le cadrage.
    public static let minimumDimension: Float = 0.05
    public static let maximumDimension: Float = 10

    public let id: UUID
    public let category: FurnitureCategory
    public let center: SIMD3<Float>
    /// Encombrement au sol : largeur puis profondeur.
    public let footprint: SIMD2<Float>
    public let height: Float
    public let yaw: Float
    public let confidence: DetectionConfidence

    public init(
        id: UUID = UUID(), category: FurnitureCategory, center: SIMD3<Float>,
        footprint: SIMD2<Float>, height: Float, yaw: Float,
        confidence: DetectionConfidence
    ) {
        self.id = id
        self.category = category
        self.center = center
        self.footprint = SIMD2(
            FurniturePiece.clamp(footprint.x), FurniturePiece.clamp(footprint.y))
        self.height = FurniturePiece.clamp(height)
        self.yaw = yaw
        self.confidence = confidence
    }

    private static func clamp(_ value: Float) -> Float {
        guard value.isFinite else { return minimumDimension }
        return min(max(abs(value), minimumDimension), maximumDimension)
    }

    public var groundPosition: SIMD2<Float> { SIMD2(center.x, center.z) }

    /// Libellé affiché à la sélection, dimensions arrondies au centimètre.
    public var dimensionsLabel: String {
        let width = Int((footprint.x * 100).rounded())
        let depth = Int((footprint.y * 100).rounded())
        let tall = Int((height * 100).rounded())
        return "\(width) × \(depth) × \(tall) cm"
    }
}
