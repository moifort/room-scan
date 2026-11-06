import RoomDressing
import RoomModel
import RoomStore
import RoomViewer
import SwiftUI

struct RoomDetailView: View {
    let store: RoomStore
    let entry: RoomEntry

    enum Presentation: Hashable { case maquette, realistic }

    @State private var room: ScannedRoom?
    @State private var modelURL: URL?
    @State private var realisticMesh: DressedMesh?
    @State private var presentation = Presentation.maquette
    @State private var failure: String?

    var body: some View {
        Group {
            if let room {
                if presentation == .realistic, let realisticMesh {
                    RealisticRoomView(mesh: realisticMesh, room: room)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    RoomMaquetteView(room: room, modelURL: modelURL)
                        .ignoresSafeArea(edges: .bottom)
                }
            } else if let failure {
                ContentUnavailableView(
                    "Pièce illisible", systemImage: "exclamationmark.triangle",
                    description: Text(failure))
            } else {
                ProgressView()
            }
        }
        .navigationTitle(entry.metadata.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Only rooms whose realistic mesh decodes offer the choice.
            if realisticMesh != nil {
                ToolbarItem(placement: .principal) {
                    Picker("Vue", selection: $presentation) {
                        Text("Maquette").tag(Presentation.maquette)
                        Text("Réaliste").tag(Presentation.realistic)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            }
        }
        .task {
            do {
                room = try store.load(id: entry.id)
                modelURL = store.modelURL(for: entry.id)
            } catch {
                failure = error.localizedDescription
                return
            }
            if let url = store.realisticMeshURL(for: entry.id) {
                // A corrupt or truncated file simply leaves the maquette alone.
                realisticMesh = await Task.detached(priority: .userInitiated) {
                    try? DressedMeshFile.decode(Data(contentsOf: url))
                }.value
            }
        }
    }
}
