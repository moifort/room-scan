import Foundation

public enum RoomStoreError: Error, Equatable, LocalizedError {
    /// Un scan sans mur ne décrit aucune pièce : on refuse de l'enregistrer.
    case unusableScan
    case unreadable(UUID)
    case unsupportedSchema(UUID, Int)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unusableScan:
            "Aucun mur n'a été détecté. Rapprochez-vous des murs et recommencez le scan."
        case .unreadable:
            "Les fichiers de cette pièce sont illisibles."
        case .unsupportedSchema:
            "Cette pièce a été enregistrée par une version plus récente de l'app."
        case .writeFailed(let reason):
            "Enregistrement impossible : \(reason)"
        }
    }
}
