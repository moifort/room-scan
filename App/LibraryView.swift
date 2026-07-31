import RoomCapture
import RoomModel
import RoomStore
import SwiftUI
import UIKit

struct LibraryView: View {
    @State private var store: RoomStore?
    @State private var entries: [RoomEntry] = []
    @State private var isScanning = false
    @State private var renaming: RoomEntry?
    @State private var newName = ""
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "Aucune pièce",
                        systemImage: "square.split.bottomrightquarter",
                        description: Text("Scannez une pièce pour commencer."))
                } else {
                    list
                }
            }
            .navigationTitle("Mes pièces")
            .toolbar { scanButton }
            .safeAreaInset(edge: .bottom) { unavailabilityNotice }
        }
        .task { reload() }
        .sheet(isPresented: $isScanning) {
            if let store {
                NavigationStack {
                    ScanFlowView(store: store) { reload() }
                }
            }
        }
        .alert("Renommer", isPresented: .constant(renaming != nil)) {
            TextField("Nom", text: $newName)
            Button("Annuler", role: .cancel) { renaming = nil }
            Button("Renommer") { commitRename() }
        }
        .alert("Erreur", isPresented: .constant(failure != nil)) {
            Button("Fermer") { failure = nil }
        } message: {
            Text(failure ?? "")
        }
    }

    private var list: some View {
        List {
            ForEach(entries) { entry in
                if entry.isReadable, let store {
                    NavigationLink {
                        RoomDetailView(store: store, entry: entry)
                    } label: {
                        row(for: entry)
                    }
                } else {
                    row(for: entry)
                }
            }
            .onDelete(perform: delete)
        }
    }

    private func row(for entry: RoomEntry) -> some View {
        HStack(spacing: 14) {
            thumbnail(for: entry)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.metadata.name)
                    .font(.headline)
                Text(entry.metadata.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !entry.isReadable {
                    Label("Fichiers illisibles", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .swipeActions(edge: .leading) {
            Button("Renommer") {
                newName = entry.metadata.name
                renaming = entry
            }
            .tint(.blue)
        }
    }

    @ViewBuilder
    private func thumbnail(for entry: RoomEntry) -> some View {
        if let url = entry.thumbnailURL, let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .frame(width: 54, height: 54)
        }
    }

    @ToolbarContentBuilder
    private var scanButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                isScanning = true
            } label: {
                Label("Scanner une pièce", systemImage: "camera.viewfinder")
            }
            .disabled(!RoomCaptureAvailability.isSupported)
        }
    }

    /// Sur simulateur ou sur un appareil sans LiDAR, dire pourquoi le bouton
    /// est inerte plutôt que de laisser l'utilisateur le presser en vain.
    @ViewBuilder
    private var unavailabilityNotice: some View {
        if !RoomCaptureAvailability.isSupported {
            Text("Le scan nécessite un iPhone équipé d'un capteur LiDAR.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(.thinMaterial)
        }
    }

    // MARK: - Actions

    private func reload() {
        do {
            let store = try self.store ?? RoomStore.documentsStore()
            self.store = store
            entries = store.entries()
        } catch {
            failure = error.localizedDescription
        }
    }

    private func delete(at offsets: IndexSet) {
        guard let store else { return }
        for index in offsets {
            try? store.delete(id: entries[index].id)
        }
        reload()
    }

    private func commitRename() {
        guard let store, let entry = renaming else { return }
        do {
            try store.rename(id: entry.id, to: newName)
        } catch {
            failure = error.localizedDescription
        }
        renaming = nil
        reload()
    }
}
