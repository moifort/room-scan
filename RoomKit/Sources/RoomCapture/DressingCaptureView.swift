#if os(iOS)
import ARKit
import RealityKit
import RoomDressing
import SwiftUI
import UIKit

/// Camera feed of the dressing pass with the captured relief laid over it:
/// grey where no sharp photo has seen it yet, blue once covered.
public struct DressingCaptureView: UIViewRepresentable {
    let session: ARSession
    let recorder: DressingRecorder

    public init(session: ARSession, recorder: DressingRecorder) {
        self.session = session
        self.recorder = recorder
    }

    public func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.session = session
        view.renderOptions.insert(.disableMotionBlur)
        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(context.coordinator.overlay)
        view.scene.addAnchor(anchor)
        return view
    }

    public func updateUIView(_ view: ARView, context: Context) {
        context.coordinator.show(recorder.overlay.mesh, covered: recorder.overlay.covered)
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    public final class Coordinator {
        let overlay = ModelEntity()
        private var shownVertexCount = -1
        private var shownCoveredCount = -1

        private static let uncovered: UnlitMaterial = {
            var m = UnlitMaterial(color: UIColor(white: 0.85, alpha: 1))
            m.blending = .transparent(opacity: 0.35)
            return m
        }()

        private static let covered: UnlitMaterial = {
            var m = UnlitMaterial(color: UIColor(red: 0.17, green: 0.70, blue: 0.85, alpha: 1))
            m.blending = .transparent(opacity: 0.45)
            return m
        }()

        func show(_ mesh: DressedMesh, covered: [Bool]) {
            let coveredCount = covered.filter { $0 }.count
            guard mesh.vertexCount != shownVertexCount || coveredCount != shownCoveredCount else { return }
            shownVertexCount = mesh.vertexCount
            shownCoveredCount = coveredCount
            guard !mesh.isEmpty, covered.count == mesh.triangleCount else {
                overlay.model = nil
                return
            }
            var descriptor = MeshDescriptor(name: "dressing-overlay")
            descriptor.positions = MeshBuffers.Positions(mesh.positions)
            descriptor.normals = MeshBuffers.Normals(mesh.normals)
            descriptor.primitives = .triangles(mesh.indices)
            descriptor.materials = .perFace(covered.map { $0 ? 1 : 0 })
            guard let resource = try? MeshResource.generate(from: [descriptor]) else { return }
            overlay.model = ModelComponent(mesh: resource, materials: [Self.uncovered, Self.covered])
        }
    }
}
#endif
