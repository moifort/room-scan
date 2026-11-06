#if os(iOS)
import RoomDressing
import RoomGeometry
import RoomModel
import SceneKit
import SwiftUI
import simd

/// The room's real shape coloured from the dressing photos, seen through an
/// orbiting camera.
public struct RealisticRoomView: View {
    private static let fieldOfView: Float = .pi / 3

    private let mesh: DressedMesh
    private let room: ScannedRoom?

    @State private var orbit: OrbitCamera
    @State private var gestureStart: OrbitCamera?
    @State private var viewSize: CGSize = .zero

    public init(mesh: DressedMesh, room: ScannedRoom? = nil) {
        self.mesh = mesh
        self.room = room
        _orbit = State(initialValue: RealisticRoomView.initialOrbit(for: mesh))
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                RealisticSceneHost(mesh: mesh, eye: orbit.position, target: orbit.target,
                                   fieldOfView: RealisticRoomView.fieldOfView)
                // Same pattern as the maquette: a transparent layer receives
                // the touches so that one drag drives the camera.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(orbitGesture)
                    .simultaneousGesture(zoomGesture)
            }
            .onAppear { viewSize = geometry.size }
            .onChange(of: geometry.size) { _, size in viewSize = size }
        }
        .background(Color(white: 0.13))
    }

    // MARK: - Gestures

    private var orbitGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let start = gestureStart ?? orbit
                if gestureStart == nil { gestureStart = start }
                var updated = start
                updated.orbit(
                    deltaAzimuth: -Float(value.translation.width) / max(Float(viewSize.width), 1) * .pi * 2,
                    deltaElevation: Float(value.translation.height) / max(Float(viewSize.height), 1) * .pi)
                orbit = updated
            }
            .onEnded { _ in gestureStart = nil }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = gestureStart ?? orbit
                if gestureStart == nil { gestureStart = start }
                var updated = start
                updated.zoom(factor: 1 / Float(max(value.magnification, 0.01)))
                orbit = updated
            }
            .onEnded { _ in gestureStart = nil }
    }

    // MARK: - Framing

    static func initialOrbit(for mesh: DressedMesh) -> OrbitCamera {
        guard let bounds = mesh.bounds else {
            return OrbitCamera(target: .zero, distance: 3, azimuth: 0.6, elevation: 0.7)
        }
        let center = (bounds.min + bounds.max) / 2
        // Half the floor diagonal: seen at an angle, the whole footprint must fit.
        let size = bounds.max - bounds.min
        let radius = simd_length(SIMD2(size.x, size.z)) / 2
        let distance = FrameFitting.distance(
            boundingRadius: max(radius, 0.5), verticalFieldOfView: fieldOfView,
            aspectRatio: 0.46)
        return OrbitCamera(target: center, distance: distance, azimuth: 0.6, elevation: 0.75)
    }
}

/// SceneKit view hosting the mesh; the camera follows the SwiftUI state.
struct RealisticSceneHost: UIViewRepresentable {
    let mesh: DressedMesh
    let eye: SIMD3<Float>
    let target: SIMD3<Float>
    let fieldOfView: Float

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = UIColor(white: 0.13, alpha: 1)
        view.antialiasingMode = .multisampling4X
        view.isUserInteractionEnabled = false

        let scene = SCNScene()
        scene.rootNode.addChildNode(RealisticSceneBuilder.node(for: mesh))
        let camera = SCNCamera()
        camera.fieldOfView = CGFloat(fieldOfView * 180 / .pi)
        camera.zNear = 0.02
        camera.zFar = 100
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
        view.scene = scene
        view.pointOfView = cameraNode
        place(cameraNode)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        if let cameraNode = view.pointOfView { place(cameraNode) }
    }

    private func place(_ node: SCNNode) {
        node.simdPosition = eye
        node.simdLook(at: target, up: [0, 1, 0], localFront: [0, 0, -1])
    }
}
#endif
