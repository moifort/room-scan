import Foundation
import simd

public enum OpeningKind: String, Codable, Hashable, Sendable, CaseIterable {
    case door, window, opening

    public var displayName: String {
        switch self {
        case .door: "Porte"
        case .window: "Fenêtre"
        case .opening: "Ouverture"
        }
    }
}

/// Une porte, une fenêtre ou une ouverture percée dans un mur.
public struct Opening: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let kind: OpeningKind
    public let center: SIMD3<Float>
    public let width: Float
    public let height: Float
    public let yaw: Float

    public init(
        id: UUID = UUID(), kind: OpeningKind, center: SIMD3<Float>,
        width: Float, height: Float, yaw: Float
    ) {
        self.id = id
        self.kind = kind
        self.center = center
        self.width = max(width, 0.01)
        self.height = max(height, 0.01)
        self.yaw = yaw
    }
}
