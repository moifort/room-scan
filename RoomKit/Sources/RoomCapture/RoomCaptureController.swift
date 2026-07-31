#if os(iOS)
import AVFoundation
import Foundation
import Observation
import RoomModel
import RoomPlan

/// Pilote un scan et expose son état. Sépare le déroulé du scan de son
/// affichage : l'écran se contente de lire `phase`, et c'est ici que vivent
/// le démarrage, l'arrêt demandé par l'utilisateur et les erreurs.
@MainActor
@Observable
public final class RoomCaptureController {
    public enum Phase: Equatable {
        case idle
        case scanning
        case processing
        case finished(ScannedRoom)
        case failed(String)
    }

    public private(set) var phase: Phase = .idle

    /// Modèle 3D exporté par RoomPlan à la fin du scan. C'est le rendu
    /// paramétrique d'Apple — celui de l'aperçu pendant la capture — nettement
    /// plus fidèle que des volumes reconstruits à la main.
    public private(set) var modelURL: URL?

    /// État observé au démarrage. Sert à expliquer un écran noir plutôt qu'à
    /// laisser l'utilisateur face à rien.
    public private(set) var diagnostics: [String] = []

    private weak var captureView: RoomCaptureView?

    public init() {}

    public var isScanning: Bool { phase == .scanning }

    public var scannedRoom: ScannedRoom? {
        if case .finished(let room) = phase { return room }
        return nil
    }

    // MARK: - Déroulé

    func attach(_ view: RoomCaptureView) {
        captureView = view
    }

    /// Démarre la capture. Appelé une fois la vue posée et dimensionnée : une
    /// session lancée sur une vue de taille nulle n'affiche aucune image.
    func startIfNeeded(viewSize: CGSize) {
        guard phase == .idle else { return }
        guard let captureView else {
            record("Vue de capture indisponible.")
            return
        }
        guard viewSize.width > 1, viewSize.height > 1 else { return }

        record("LiDAR : \(RoomCaptureSession.isSupported ? "disponible" : "indisponible")")
        record("Caméra : \(cameraAuthorizationDescription)")
        record("Vue : \(Int(viewSize.width))×\(Int(viewSize.height))")

        guard RoomCaptureSession.isSupported else {
            phase = .failed("Cet appareil ne prend pas en charge le scan de pièces.")
            return
        }
        guard AVCaptureDevice.authorizationStatus(for: .video) != .denied else {
            phase = .failed(
                "L'accès à la caméra est refusé. Autorisez-le dans Réglages pour scanner.")
            return
        }

        captureView.captureSession.run(configuration: RoomCaptureSession.Configuration())
        phase = .scanning
        record("Session démarrée.")
    }

    /// Termine le scan à la demande de l'utilisateur : c'est l'arrêt de la
    /// session qui déclenche le post-traitement, donc le résultat.
    public func finish() {
        guard phase == .scanning else { return }
        phase = .processing
        captureView?.captureSession.stop()
    }

    /// Abandon : arrêter sans attendre de résultat.
    public func cancel() {
        guard phase == .scanning || phase == .processing else { return }
        captureView?.captureSession.stop()
        phase = .idle
    }

    // MARK: - Retours du délégué

    func handleSuccess(_ room: ScannedRoom, modelURL: URL?) {
        self.modelURL = modelURL
        if modelURL == nil {
            record("Modèle 3D non exporté : affichage de repli.")
        }
        phase = .finished(room)
    }

    func handleFailure(_ message: String) {
        record("Erreur : \(message)")
        phase = .failed(message)
    }

    private func record(_ line: String) {
        diagnostics.append(line)
    }

    private var cameraAuthorizationDescription: String {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: "autorisée"
        case .denied: "refusée"
        case .restricted: "restreinte"
        case .notDetermined: "pas encore demandée"
        @unknown default: "état inconnu"
        }
    }
}
#endif
