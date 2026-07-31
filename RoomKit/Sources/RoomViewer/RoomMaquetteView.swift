#if os(iOS)
import RealityKit
import RoomGeometry
import RoomModel
import SwiftUI
import simd

/// Maquette 3D d'une pièce : sol, murs, ouvertures et meubles, observés par
/// une caméra orbitale.
public struct RoomMaquetteView: View {
    private static let fieldOfView: Float = .pi / 3

    private let room: ScannedRoom

    @State private var camera: OrbitCamera
    @State private var builder: RoomSceneBuilder
    @State private var cameraEntity = PerspectiveCamera()

    public init(room: ScannedRoom) {
        self.room = room
        _builder = State(initialValue: RoomSceneBuilder(room: room))
        _camera = State(initialValue: FrameFitting.initialCamera(
            for: room, verticalFieldOfView: RoomMaquetteView.fieldOfView, aspectRatio: 0.46))
    }

    public var body: some View {
        GeometryReader { geometry in
            RealityView { content in
                content.add(builder.buildScene())
                cameraEntity.camera.fieldOfViewInDegrees = RoomMaquetteView.fieldOfView * 180 / .pi
                content.add(cameraEntity)
                applyCamera()
            }
            .onAppear { fitCamera(to: geometry.size) }
            .onChange(of: camera) { applyCamera() }
        }
        .background(Color(white: 0.13))
    }

    private func fitCamera(to size: CGSize) {
        guard size.height > 0 else { return }
        camera = FrameFitting.initialCamera(
            for: room,
            verticalFieldOfView: RoomMaquetteView.fieldOfView,
            aspectRatio: Float(size.width / size.height))
    }

    private func applyCamera() {
        let eye = camera.position
        cameraEntity.position = eye
        cameraEntity.look(at: camera.target, from: eye, relativeTo: nil)
        updateWallVisibility()
    }

    private func updateWallVisibility() {
        let hidden = WallVisibility.hiddenWallIDs(
            walls: room.walls, roomCenter: room.floor.center, cameraPosition: camera.position)

        for (id, entity) in builder.wallEntities {
            entity.isEnabled = !hidden.contains(id)
        }
    }
}
#endif
