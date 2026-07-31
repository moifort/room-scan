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
    private let modelURL: URL?

    @State private var camera: OrbitCamera
    @State private var builder: RoomSceneBuilder
    @State private var cameraEntity = PerspectiveCamera()
    @State private var gestureStartCamera: OrbitCamera?
    @State private var viewSize: CGSize = .zero
    @State private var selection: UUID?
    @State private var isInventoryPresented = false

    public init(room: ScannedRoom, modelURL: URL? = nil) {
        self.room = room
        self.modelURL = modelURL
        _builder = State(initialValue: RoomSceneBuilder(room: room))
        _camera = State(initialValue: FrameFitting.initialCamera(
            for: room, verticalFieldOfView: RoomMaquetteView.fieldOfView, aspectRatio: 0.46))
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                RealityView { content in
                    content.add(await builder.buildScene(modelURL: modelURL))
                    cameraEntity.camera.fieldOfViewInDegrees =
                        RoomMaquetteView.fieldOfView * 180 / .pi
                    content.add(cameraEntity)
                    applyCamera()
                }

                // RealityView absorbe les touches : aucun geste qu'on lui
                // attache ne se déclenche. Cette couche transparente posée
                // par-dessus les reçoit à sa place.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(orbitOrTapGesture)
                    .simultaneousGesture(zoomGesture)
            }
            .overlay(alignment: .bottomTrailing) { cameraButtons }
            .overlay(alignment: .bottom) {
                if let piece = selectedPiece {
                    SelectionOverlay(piece: piece) { clearSelection() }
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: selection)
            .sheet(isPresented: $isInventoryPresented) {
                NavigationStack {
                    InventoryPanel(room: room, selection: selection) { id in
                        selectFromInventory(id)
                    }
                    .navigationTitle("Meubles reconnus")
                    .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.medium, .large])
            }
            .onAppear {
                viewSize = geometry.size
                fitCamera(to: geometry.size)
            }
            .onChange(of: geometry.size) { _, newSize in viewSize = newSize }
            .onChange(of: camera) { applyCamera() }
        }
        .background(Color(white: 0.13))
    }

    // MARK: - Gestes

    /// Distance en deçà de laquelle un glissement compte comme un simple appui.
    private static let tapTolerance: CGFloat = 6

    /// Un seul geste pour l'orbite et la sélection. Deux gestes concurrents ne
    /// cohabitent pas sur une RealityView : le glissement capte la séquence
    /// tactile et le tap séparé ne se conclut jamais. On distingue donc les
    /// deux à la fin du même geste, selon la distance parcourue.
    private var orbitOrTapGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard travelled(value) > RoomMaquetteView.tapTolerance else { return }

                let start = gestureStartCamera ?? camera
                if gestureStartCamera == nil { gestureStartCamera = start }

                // Un balayage sur toute la largeur fait un tour complet.
                let width = max(Float(viewSize.width), 1)
                let height = max(Float(viewSize.height), 1)
                var updated = start
                updated.orbit(
                    deltaAzimuth: -Float(value.translation.width) / width * .pi * 2,
                    deltaElevation: Float(value.translation.height) / height * .pi)
                camera = updated
            }
            .onEnded { value in
                if travelled(value) <= RoomMaquetteView.tapTolerance {
                    select(at: value.startLocation)
                }
                gestureStartCamera = nil
            }
    }

    private func travelled(_ value: DragGesture.Value) -> CGFloat {
        let translation = value.translation
        return (translation.width * translation.width
            + translation.height * translation.height).squareRoot()
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = gestureStartCamera ?? camera
                if gestureStartCamera == nil { gestureStartCamera = start }

                var updated = start
                updated.zoom(factor: 1 / Float(max(value.magnification, 0.01)))
                camera = updated
            }
            .onEnded { _ in gestureStartCamera = nil }
    }

    private var cameraButtons: some View {
        VStack(spacing: 14) {
            Button {
                var updated = camera
                updated.topDown()
                camera = updated
            } label: {
                Image(systemName: "arrow.down.to.line")
            }
            .accessibilityLabel("Vue de dessus")

            Button {
                fitCamera(to: viewSize)
            } label: {
                Image(systemName: "viewfinder")
            }
            .accessibilityLabel("Recadrer sur la pièce")

            Button {
                isInventoryPresented = true
            } label: {
                Image(systemName: "list.bullet")
            }
            .accessibilityLabel("Inventaire des meubles")
        }
        .font(.title2)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(20)
    }

    // MARK: - Sélection

    private var selectedPiece: FurniturePiece? {
        guard let selection else { return nil }
        return room.furniture.first { $0.id == selection }
    }

    private func select(at location: CGPoint) {
        guard let id = FurniturePicking.pick(
            at: SIMD2(Float(location.x), Float(location.y)),
            viewSize: SIMD2(Float(viewSize.width), Float(viewSize.height)),
            camera: camera,
            verticalFieldOfView: RoomMaquetteView.fieldOfView,
            furniture: room.furniture)
        else {
            // Toucher à côté de tout meuble referme la fiche courante.
            clearSelection()
            return
        }

        highlight(id)
    }

    private func selectFromInventory(_ id: UUID) {
        highlight(id)
        isInventoryPresented = false
    }

    private func highlight(_ id: UUID) {
        if let previous = selection { builder.setHighlight(false, forFurniture: previous) }
        selection = id
        builder.setHighlight(true, forFurniture: id)
    }

    private func clearSelection() {
        guard let previous = selection else { return }
        builder.setHighlight(false, forFurniture: previous)
        selection = nil
    }

    // MARK: - Caméra

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
