import RoomModel
import RoomStore
import RoomViewer
import SwiftUI

struct RoomDetailView: View {
    let store: RoomStore
    let entry: RoomEntry

    @State private var room: ScannedRoom?
    @State private var modelURL: URL?
    @State private var failure: String?

    var body: some View {
        Group {
            if let room {
                RoomMaquetteView(room: room, modelURL: modelURL)
                    .ignoresSafeArea(edges: .bottom)
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
        .task {
            do {
                room = try store.load(id: entry.id)
                modelURL = store.modelURL(for: entry.id)
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}
