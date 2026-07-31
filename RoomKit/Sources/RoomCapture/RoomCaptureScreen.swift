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

/// Reçoit les événements de RoomPlan et les transmet au contrôleur.
///
/// Classe de premier niveau et non imbriquée : le protocole délégué de RoomPlan
/// n'est pas isolé au main actor, ses méthodes sont donc appelées hors de lui et
/// ne peuvent pas vivre dans un type isolé.
public final class RoomCaptureCoordinator: NSObject, RoomCaptureViewDelegate, @unchecked Sendable {
    private let controller: RoomCaptureController

    init(controller: RoomCaptureController) {
        self.controller = controller
    }

    // `RoomCaptureViewDelegate` hérite de `NSCoding`. Ce coordinateur ne vit
    // que le temps d'un scan et n'a rien à archiver : les exigences du
    // protocole sont satisfaites sans rien conserver.
    public func encode(with coder: NSCoder) {}

    public required init?(coder: NSCoder) { nil }

    /// Accepter le post-traitement : c'est lui qui produit la pièce propre.
    public func captureView(
        shouldPresent roomDataForProcessing: CapturedRoomData, error: (any Error)?
    ) -> Bool {
        if let error {
            report(failure: error.localizedDescription)
            return false
        }
        return true
    }

    public func captureView(didPresent processedResult: CapturedRoom, error: (any Error)?) {
        if let error {
            report(failure: error.localizedDescription)
            return
        }
        // La traduction a lieu ici : au-delà ne circulent qu'un `ScannedRoom`
        // et une URL, qui traversent sans risque la frontière d'isolation.
        let room = CapturedRoomTranslator.translate(processedResult)
        let modelURL = exportModel(from: processedResult)
        let controller = controller
        Task { @MainActor in controller.handleSuccess(room, modelURL: modelURL) }
    }

    /// Exporte le modèle paramétrique — celui affiché par RoomPlan pendant le
    /// scan. L'échec n'est pas bloquant : la maquette de repli reste affichable.
    private func exportModel(from room: CapturedRoom) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("room-\(UUID().uuidString).usdz")
        do {
            try room.export(to: url, exportOptions: .parametric)
            return url
        } catch {
            return nil
        }
    }

    private func report(failure message: String) {
        let controller = controller
        Task { @MainActor in controller.handleFailure(message) }
    }
}

/// Héberge la vue de RoomPlan et démarre la session au bon moment.
///
/// Un contrôleur plutôt qu'une simple vue : `viewDidAppear` est le seul
/// déclencheur qui garantit que la vue est posée **et** dimensionnée. Démarrée
/// plus tôt, la session n'affiche rien et ne demande même pas l'accès caméra.
public final class RoomCaptureHostController: UIViewController {
    private let controller: RoomCaptureController
    private let coordinator: RoomCaptureCoordinator
    private var captureView: RoomCaptureView?

    init(controller: RoomCaptureController, coordinator: RoomCaptureCoordinator) {
        self.controller = controller
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    public override func viewDidLoad() {
        super.viewDidLoad()

        let capture = RoomCaptureView(frame: view.bounds)
        capture.translatesAutoresizingMaskIntoConstraints = false
        capture.delegate = coordinator
        view.addSubview(capture)

        NSLayoutConstraint.activate([
            capture.topAnchor.constraint(equalTo: view.topAnchor),
            capture.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            capture.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            capture.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        captureView = capture
        controller.attach(capture)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        controller.startIfNeeded(viewSize: captureView?.bounds.size ?? view.bounds.size)
    }
}

/// Écran de capture fourni par RoomPlan : guidage, surlignage temps réel et
/// animation de fin. On n'écrit que le pilotage et la traduction du résultat.
public struct RoomCaptureScreen: UIViewControllerRepresentable {
    private let controller: RoomCaptureController

    public init(controller: RoomCaptureController) {
        self.controller = controller
    }

    public func makeUIViewController(context: Context) -> RoomCaptureHostController {
        RoomCaptureHostController(controller: controller, coordinator: context.coordinator)
    }

    public func updateUIViewController(
        _ uiViewController: RoomCaptureHostController, context: Context
    ) {}

    public func makeCoordinator() -> RoomCaptureCoordinator {
        RoomCaptureCoordinator(controller: controller)
    }
}
#endif
