import Foundation

/// Fiabilité de la reconnaissance telle que rendue par le scanner.
public enum DetectionConfidence: String, Codable, Hashable, Sendable, CaseIterable {
    case high, medium, low

    /// Seule une confiance élevée est présentée sans réserve à l'utilisateur.
    public var isCertain: Bool { self == .high }
}
