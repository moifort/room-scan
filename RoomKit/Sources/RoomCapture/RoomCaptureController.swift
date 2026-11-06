#if os(iOS)
import ARKit
import AVFoundation
import Foundation
import Observation
import RoomDressing
import RoomModel
import RoomPlan

/// Drives a scan and exposes its state: the structure scan by RoomPlan, then
/// the dressing pass on the same ARKit session, then the colouring. The
/// screen only reads `phase`; ordering lives in `CaptureFlow`.
@MainActor
@Observable
public final class RoomCaptureController {
    public typealias Phase = CaptureFlow<ScannedRoom>.Phase

    private var flow = CaptureFlow<ScannedRoom>()
    public var phase: Phase { flow.phase }

    /// Apple's parametric model exported at the end of the structure scan.
    public private(set) var modelURL: URL?

    /// Startup and dressing facts, shown before the scan starts and written
    /// to `dressing.log` with the room.
    public private(set) var diagnostics: [String] = []

    /// One session for both passes: RoomPlan runs on it, then the dressing
    /// pass keeps it running, so both share one world frame.
    public let arSession = ARSession()

    public private(set) var recorder: DressingRecorder?

    /// The dressing workspace, once its colours are computed. Nil when the
    /// dressing was skipped, empty or failed.
    public var dressing: DressingWorkspace? {
        if case .finished(_, dressed: true) = phase { return workspace }
        return nil
    }

    public var dressingFailed: Bool { flow.dressingFailed }

    private weak var captureView: RoomCaptureView?
    private var workspace: DressingWorkspace?
    private var dressingMesh: DressedMesh?
    private var colouringTask: Task<Void, Never>?

    public init() {}

    public var isScanning: Bool { phase == .scanning }
    public var isDressing: Bool { phase == .dressing }

    public var scannedRoom: ScannedRoom? {
        if case .finished(let room, _) = phase { return room }
        return nil
    }

    // MARK: - Structure scan

    func attach(_ view: RoomCaptureView) {
        captureView = view
    }

    /// Starts the capture once the view is laid out and sized: a session
    /// started on a zero-sized view shows no image.
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
            flow.handle(.started)
            flow.handle(.structureFailed("Cet appareil ne prend pas en charge le scan de pièces."))
            return
        }
        guard AVCaptureDevice.authorizationStatus(for: .video) != .denied else {
            flow.handle(.started)
            flow.handle(.structureFailed(
                "L'accès à la caméra est refusé. Autorisez-le dans Réglages pour scanner."))
            return
        }

        captureView.captureSession.run(configuration: RoomCaptureSession.Configuration())
        flow.handle(.started)
        record("Session démarrée.")
    }

    /// Ends the structure scan and moves straight to the dressing pass,
    /// without stopping the camera. RoomPlan's processing runs meanwhile.
    public func finish() {
        guard phase == .scanning else { return }
        flow.handle(.structureFinishRequested)
        captureView?.captureSession.stop(pauseARSession: false)
        do {
            let workspace = try DressingWorkspace.create(in: FileManager.default.temporaryDirectory)
            self.workspace = workspace
            let recorder = DressingRecorder(session: arSession, workspace: workspace)
            self.recorder = recorder
            recorder.start()
            record("Habillage démarré.")
        } catch {
            record("Habillage impossible : \(error.localizedDescription)")
            arSession.pause()
            flow.handle(.dressingSkipped)
        }
    }

    // MARK: - Dressing

    public func finishDressing() {
        guard phase == .dressing, let recorder else { return }
        Task { @MainActor in
            let capture = await recorder.stop()
            self.recorder = nil
            arSession.pause()
            dressingMesh = capture.mesh
            record("Photos retenues : \(capture.manifest.keyframes.count)")
            record("Relief : \(capture.mesh.vertexCount) sommets, \(capture.mesh.triangleCount) faces")
            record("Mémoire disponible : \(os_proc_available_memory() / 1_048_576) Mo")
            recordAlignment()
            flow.handle(.dressingFinished(hasContent: capture.hasContent))
            if capture.hasContent { colour(capture.mesh) } else { discardWorkspace() }
        }
    }

    public func skipDressing() {
        guard phase == .dressing else { return }
        recorder?.cancel()
        recorder = nil
        arSession.pause()
        discardWorkspace()
        record("Habillage passé.")
        flow.handle(.dressingSkipped)
    }

    private func colour(_ mesh: DressedMesh) {
        guard let workspace else { return }
        let started = Date()
        colouringTask = Task { @MainActor in
            do {
                try await ColouringJob.run(mesh: mesh, workspace: workspace) { progress in
                    Task { @MainActor in self.flow.handle(.colouringProgressed(progress)) }
                }
                record("Mise en couleurs : \(Int(Date().timeIntervalSince(started))) s")
                writeLog()
                flow.handle(.colouringSucceeded)
            } catch is CancellationError {
                return
            } catch {
                record("Mise en couleurs impossible : \(error.localizedDescription)")
                flow.handle(.colouringFailed)
            }
        }
    }

    // MARK: - Ending

    /// Abandon: stop everything and throw the dressing away.
    public func cancel() {
        colouringTask?.cancel()
        colouringTask = nil
        recorder?.cancel()
        recorder = nil
        if phase == .scanning { captureView?.captureSession.stop() }
        arSession.pause()
        discardWorkspace()
        flow.handle(.cancelled)
    }

    /// Called once the room is saved (the store copies what it keeps).
    public func discardWorkspace() {
        workspace?.discard()
        workspace = nil
    }

    // MARK: - RoomPlan delegate

    func handleSuccess(_ room: ScannedRoom, modelURL: URL?) {
        self.modelURL = modelURL
        if modelURL == nil {
            record("Modèle 3D non exporté : affichage de repli.")
        }
        flow.handle(.structureArrived(room))
        recordAlignment()
    }

    func handleFailure(_ message: String) {
        record("Erreur : \(message)")
        flow.handle(.structureFailed(message))
    }

    // MARK: - Diagnostics

    /// Distance between the ARKit relief and RoomPlan's walls: both passes
    /// must share one frame for the realistic view to line up.
    private func recordAlignment() {
        guard let mesh = dressingMesh, let room = flow.structure else { return }
        if let distance = WallAlignment.medianDistance(of: mesh, to: room.walls) {
            record(String(format: "Écart médian relief/murs : %.1f cm", distance * 100))
        } else {
            record("Écart relief/murs : aucun mur dans le relief")
        }
        writeLog()
    }

    private func writeLog() {
        guard let workspace else { return }
        try? diagnostics.joined(separator: "\n")
            .write(to: workspace.root.appendingPathComponent("dressing.log"),
                   atomically: true, encoding: .utf8)
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
