#if os(iOS)
import ARKit
import Foundation
import Observation
import RoomDressing

/// Everything the dressing pass collected, handed to the colouring job.
public struct DressingCapture: Sendable {
    public var mesh: DressedMesh
    public var manifest: KeyframeManifest
    public var hasContent: Bool { !mesh.isEmpty && !manifest.keyframes.isEmpty }
}

/// Keeps the coverage and the latest fused mesh off the main thread.
actor DressingProcessor {
    private var tracker = CoverageTracker()
    private var views: [ColorView] = []
    private(set) var mesh = DressedMesh.empty

    /// Fuses the current mesh anchors; returns the mesh, its covered
    /// triangles and the covered fraction.
    func update(pieces: [MeshPiece]) -> (mesh: DressedMesh, covered: [Bool], fraction: Float) {
        mesh = MeshFusion.fuse(pieces)
        let covered = (0..<mesh.triangleCount).map { tracker.isCovered(triangle: $0, in: mesh) }
        return (mesh, covered, tracker.fraction(of: mesh))
    }

    func mark(_ view: ColorView) -> Float {
        views.append(view)
        tracker.markSeen(by: view, mesh: mesh)
        return tracker.fraction(of: mesh)
    }
}

/// Drives the dressing pass on the ARKit session RoomPlan just released:
/// runs mesh reconstruction, keeps sharp and novel photos, and reports the
/// coverage for the live overlay.
///
/// Frames are polled rather than received as the session delegate: RoomPlan
/// owned that delegate during the structure scan, and polling `currentFrame`
/// was proven on the device by the probe.
@MainActor
@Observable
public final class DressingRecorder {
    public private(set) var acceptedCount = 0
    public private(set) var isMovingTooFast = false
    public private(set) var coverage: Float = 0
    public private(set) var vertexCount = 0
    /// Latest fused mesh and which of its triangles are covered.
    public private(set) var overlay: (mesh: DressedMesh, covered: [Bool]) = (.empty, [])

    private let session: ARSession
    private let workspace: DressingWorkspace
    private let writer: KeyframeWriter
    private let processor = DressingProcessor()
    private let writeQueue = DispatchQueue(label: "dressing.keyframes", qos: .userInitiated)
    private var selector = KeyframeSelector()
    private var records: [KeyframeRecord] = []
    private var pendingWrites = 0
    private var nextIndex = 0
    private var timer: Timer?
    private var tick = 0
    private var isUpdatingMesh = false

    static let maxPendingWrites = 2

    public init(session: ARSession, workspace: DressingWorkspace) {
        self.session = session
        self.workspace = workspace
        writer = KeyframeWriter(workspace: workspace)
    }

    /// Switches the session to mesh reconstruction without resetting
    /// tracking, so the world frame stays that of the RoomPlan result.
    public func start() {
        let configuration = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            configuration.sceneReconstruction = .meshWithClassification
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics = [.sceneDepth]
        }
        session.run(configuration, options: [])
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
    }

    /// Stops sampling and returns what was captured, once pending photos are written.
    public func stop() async -> DressingCapture {
        timer?.invalidate()
        timer = nil
        let pieces = meshPieces()
        while pendingWrites > 0 {
            try? await Task.sleep(for: .milliseconds(50))
        }
        let fused = await processor.update(pieces: pieces)
        let manifest = KeyframeManifest(keyframes: records.sorted { $0.file < $1.file })
        try? workspace.write(manifest)
        return DressingCapture(mesh: fused.mesh, manifest: manifest)
    }

    public func cancel() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Sampling

    private func sample() {
        tick += 1
        guard let frame = session.currentFrame else { return }
        let decision = selector.evaluate(
            time: frame.timestamp, transform: frame.camera.transform,
            trackingNormal: frame.camera.trackingState == .normal)
        isMovingTooFast = selector.isMovingTooFast
        if decision == .accept { keep(frame) }
        if tick % 10 == 0 { refreshMesh() }
    }

    private func keep(_ frame: ARFrame) {
        guard pendingWrites < Self.maxPendingWrites, let depth = frame.sceneDepth else { return }
        pendingWrites += 1
        let index = nextIndex
        nextIndex += 1
        let image = PixelBufferBox(buffer: frame.capturedImage)
        let depthBox = PixelBufferBox(buffer: depth.depthMap)
        let confidence = depth.confidenceMap.map(PixelBufferBox.init)
        let pose = CameraPose(frame.camera)
        let timestamp = frame.timestamp
        let writer = writer
        let processor = processor

        writeQueue.async { [weak self] in
            let result = try? writer.write(image: image, depth: depthBox, confidence: confidence,
                                           pose: pose, timestamp: timestamp, index: index)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pendingWrites -= 1
                guard let result else { return }
                self.records.append(result.record)
                self.acceptedCount = self.records.count
                let view = ColorView(pose: pose, depth: result.depth, sharpness: result.record.sharpness)
                self.coverage = await processor.mark(view)
            }
        }
    }

    private func refreshMesh() {
        guard !isUpdatingMesh else { return }
        isUpdatingMesh = true
        let pieces = meshPieces()
        let processor = processor
        Task { @MainActor [weak self] in
            let result = await processor.update(pieces: pieces)
            guard let self else { return }
            self.overlay = (result.mesh, result.covered)
            self.coverage = result.fraction
            self.vertexCount = result.mesh.vertexCount
            self.isUpdatingMesh = false
        }
    }

    private func meshPieces() -> [MeshPiece] {
        (session.currentFrame?.anchors ?? []).compactMap { $0 as? ARMeshAnchor }.map(MeshPiece.init)
    }
}
#endif
