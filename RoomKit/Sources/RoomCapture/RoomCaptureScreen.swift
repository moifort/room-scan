#if os(iOS)
import RoomModel
import RoomPlan
import SwiftUI

public enum RoomCaptureAvailability {
    /// Faux sur simulateur et sur tout appareil dépourvu de LiDAR.
    public static var isSupported: Bool { RoomCaptureSession.isSupported }
}

public enum RoomCaptureError: Error, LocalizedError {
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .failed(let reason): "Le scan a échoué : \(reason)"
        }
    }
}

/// Reçoit les événements de RoomPlan et rend une pièce traduite.
///
/// Classe de premier niveau et non imbriquée : le protocole délégué de RoomPlan
/// n'est pas isolé au main actor, ses méthodes sont donc appelées hors de lui et
/// ne peuvent pas vivre dans un type isolé.
public final class RoomCaptureCoordinator: NSObject, RoomCaptureViewDelegate, @unchecked Sendable {
    private let onFinished: @MainActor @Sendable (Result<ScannedRoom, any Error>) -> Void
    private var isRunning = false

    init(onFinished: @escaping @MainActor @Sendable (Result<ScannedRoom, any Error>) -> Void) {
        self.onFinished = onFinished
    }

    // `RoomCaptureViewDelegate` hérite de `NSCoding`. Ce coordinateur ne vit
    // que le temps d'un scan et n'a rien à archiver : les exigences du
    // protocole sont satisfaites sans rien conserver.
    public func encode(with coder: NSCoder) {}

    public required init?(coder: NSCoder) { nil }

    @MainActor
    func start(_ view: RoomCaptureView) {
        guard !isRunning else { return }
        isRunning = true
        view.captureSession.run(configuration: RoomCaptureSession.Configuration())
    }

    @MainActor
    func stop(_ view: RoomCaptureView) {
        guard isRunning else { return }
        isRunning = false
        view.captureSession.stop()
    }

    /// Accepter le post-traitement : c'est lui qui produit la pièce propre.
    public func captureView(
        shouldPresent roomDataForProcessing: CapturedRoomData, error: (any Error)?
    ) -> Bool {
        if let error {
            finish(.failure(RoomCaptureError.failed(error.localizedDescription)))
            return false
        }
        return true
    }

    public func captureView(didPresent processedResult: CapturedRoom, error: (any Error)?) {
        isRunning = false
        if let error {
            finish(.failure(RoomCaptureError.failed(error.localizedDescription)))
        } else {
            // La traduction a lieu ici : au-delà ne circule qu'un `ScannedRoom`,
            // qui traverse sans risque la frontière d'isolation.
            finish(.success(CapturedRoomTranslator.translate(processedResult)))
        }
    }

    private func finish(_ result: Result<ScannedRoom, any Error>) {
        let callback = onFinished
        Task { @MainActor in callback(result) }
    }
}

/// Écran de capture fourni par RoomPlan : guidage, surlignage temps réel et
/// animation de fin. On n'écrit que la traduction du résultat.
public struct RoomCaptureScreen: UIViewRepresentable {
    private let onFinished: @MainActor @Sendable (Result<ScannedRoom, any Error>) -> Void

    public init(
        onFinished: @escaping @MainActor @Sendable (Result<ScannedRoom, any Error>) -> Void
    ) {
        self.onFinished = onFinished
    }

    public func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        view.delegate = context.coordinator
        context.coordinator.start(view)
        return view
    }

    public func updateUIView(_ view: RoomCaptureView, context: Context) {}

    public func makeCoordinator() -> RoomCaptureCoordinator {
        RoomCaptureCoordinator(onFinished: onFinished)
    }

    public static func dismantleUIView(
        _ view: RoomCaptureView, coordinator: RoomCaptureCoordinator
    ) {
        MainActor.assumeIsolated { coordinator.stop(view) }
    }
}
#endif
