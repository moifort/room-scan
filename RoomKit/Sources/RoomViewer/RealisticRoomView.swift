#if os(iOS)
import RoomDressing
import RoomGeometry
import RoomModel
import SceneKit
import SwiftUI
import simd

/// The room's real shape coloured from the dressing photos. Seen from
/// outside with an orbiting camera, or from inside at eye height: drag to
/// look around, tap the floor to walk there.
public struct RealisticRoomView: View {
    private static let fieldOfView: Float = .pi / 3
    private static let tapTolerance: CGFloat = 6

    enum Mode { case orbit, eyeLevel }

    private let mesh: DressedMesh
    private let room: ScannedRoom?

    @State private var mode = Mode.orbit
    @State private var orbit: OrbitCamera
    @State private var visitor: FirstPersonCamera
    @State private var orbitStart: OrbitCamera?
    @State private var visitorStart: FirstPersonCamera?
    @State private var viewSize: CGSize = .zero

    public init(mesh: DressedMesh, room: ScannedRoom? = nil) {
        self.mesh = mesh
        self.room = room
        // With the scan at hand, frame like the maquette so switching views
        // keeps the same point of view.
        _orbit = State(initialValue: room.map {
            FrameFitting.initialCamera(for: $0, verticalFieldOfView: RealisticRoomView.fieldOfView,
                                       aspectRatio: 0.46)
        } ?? RealisticRoomView.initialOrbit(for: mesh))
        _visitor = State(initialValue: RealisticRoomView.initialVisitor(for: mesh, room: room))
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                RealisticSceneHost(mesh: mesh, eye: eye, target: target,
                                   fieldOfView: RealisticRoomView.fieldOfView)
                // Same pattern as the maquette: a transparent layer receives
                // the touches so that one drag drives the camera.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(dragOrTapGesture)
                    .simultaneousGesture(zoomGesture)
            }
            .overlay(alignment: .bottomTrailing) { modeButton }
            .onAppear { viewSize = geometry.size }
            .onChange(of: geometry.size) { _, size in viewSize = size }
        }
        .background(Color(white: 0.13))
    }

    private var eye: SIMD3<Float> { mode == .orbit ? orbit.position : visitor.position }
    private var target: SIMD3<Float> {
        mode == .orbit ? orbit.target : visitor.position + visitor.forward
    }

    private var modeButton: some View {
        Button {
            withAnimation(.snappy) { mode = mode == .orbit ? .eyeLevel : .orbit }
        } label: {
            Label(mode == .orbit ? "À hauteur d'yeux" : "Vue d'ensemble",
                  systemImage: mode == .orbit ? "figure.walk" : "cube")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
        }
        .padding(20)
    }

    // MARK: - Gestures

    private var dragOrTapGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard travelled(value) > RealisticRoomView.tapTolerance else { return }
                let dx = Float(value.translation.width) / max(Float(viewSize.width), 1)
                let dy = Float(value.translation.height) / max(Float(viewSize.height), 1)
                switch mode {
                case .orbit:
                    let start = orbitStart ?? orbit
                    if orbitStart == nil { orbitStart = start }
                    var updated = start
                    updated.orbit(deltaAzimuth: -dx * .pi * 2, deltaElevation: dy * .pi)
                    orbit = updated
                case .eyeLevel:
                    // Dragging moves the room under the finger, like turning one's head.
                    let start = visitorStart ?? visitor
                    if visitorStart == nil { visitorStart = start }
                    var updated = start
                    updated.look(deltaYaw: dx * .pi, deltaPitch: dy * .pi / 2)
                    visitor = updated
                }
            }
            .onEnded { value in
                if travelled(value) <= RealisticRoomView.tapTolerance, mode == .eyeLevel {
                    walk(toward: value.startLocation)
                }
                orbitStart = nil
                visitorStart = nil
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard mode == .orbit else { return }
                let start = orbitStart ?? orbit
                if orbitStart == nil { orbitStart = start }
                var updated = start
                updated.zoom(factor: 1 / Float(max(value.magnification, 0.01)))
                orbit = updated
            }
            .onEnded { _ in orbitStart = nil }
    }

    private func travelled(_ value: DragGesture.Value) -> CGFloat {
        hypot(value.translation.width, value.translation.height)
    }

    private func walk(toward location: CGPoint) {
        let width = max(Float(viewSize.width), 1), height = max(Float(viewSize.height), 1)
        let point = SIMD2(Float(location.x) / width * 2 - 1, 1 - Float(location.y) / height * 2)
        guard let hit = visitor.floorHit(
            normalizedScreenPoint: point, verticalFieldOfView: RealisticRoomView.fieldOfView,
            aspectRatio: width / height)
        else { return }
        var updated = visitor
        updated.walk(to: hit, within: outline)
        visitor = updated
    }

    private var outline: FloorOutline {
        if let room, !room.floor.isEmpty { return room.floor }
        guard let bounds = mesh.bounds else { return FloorOutline(points: []) }
        return FloorOutline(points: [
            SIMD2(bounds.min.x, bounds.min.z), SIMD2(bounds.max.x, bounds.min.z),
            SIMD2(bounds.max.x, bounds.max.z), SIMD2(bounds.min.x, bounds.max.z)])
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

    /// Stands in the middle of the captured floor: the scan's floor outline is
    /// a bounding rectangle, whose centre can sit outside an L-shaped room.
    static func initialVisitor(for mesh: DressedMesh, room: ScannedRoom?) -> FirstPersonCamera {
        var floorSum = SIMD2<Float>.zero
        var floorCount = 0
        for t in 0..<mesh.triangleCount where mesh.faceClasses[t] == MeshClass.floor.rawValue {
            let c = mesh.centroid(ofTriangle: t)
            floorSum += SIMD2(c.x, c.z)
            floorCount += 1
        }
        if floorCount > 0 {
            return FirstPersonCamera(floorPoint: floorSum / Float(floorCount),
                                     floorHeight: room?.floorHeight ?? mesh.bounds?.min.y ?? 0)
        }
        if let room, !room.floor.isEmpty {
            return FirstPersonCamera(floorPoint: room.floor.center, floorHeight: room.floorHeight)
        }
        guard let bounds = mesh.bounds else {
            return FirstPersonCamera(floorPoint: .zero, floorHeight: 0)
        }
        let center = (bounds.min + bounds.max) / 2
        return FirstPersonCamera(floorPoint: SIMD2(center.x, center.z), floorHeight: bounds.min.y)
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
        place(cameraNode, animated: false)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        if let cameraNode = view.pointOfView { place(cameraNode, animated: true) }
    }

    /// Big jumps (walking to a tapped point, switching mode) glide; small
    /// ones (dragging) follow the finger directly.
    private func place(_ node: SCNNode, animated: Bool) {
        let jump = simd_distance(node.simdPosition, eye)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated && jump > 0.3 ? 0.45 : 0
        node.simdPosition = eye
        node.simdLook(at: target, up: [0, 1, 0], localFront: [0, 0, -1])
        SCNTransaction.commit()
    }
}
#endif
