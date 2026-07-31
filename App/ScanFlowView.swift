import RoomCapture
import RoomModel
import RoomStore
import RoomViewer
import SwiftUI

/// Enchaîne le scan, le nommage et l'enregistrement.
struct ScanFlowView: View {
    let store: RoomStore
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var scanned: ScannedRoom?
    @State private var name = ""
    @State private var failure: String?

    var body: some View {
        Group {
            if let scanned {
                summary(for: scanned)
            } else {
                RoomCaptureScreen { result in
                    switch result {
                    case .success(let room): scanned = room
                    case .failure(let error): failure = error.localizedDescription
                    }
                }
                .ignoresSafeArea()
                .navigationTitle("Scan en cours")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(scanned == nil ? "Annuler" : "Recommencer") {
                    if scanned == nil { dismiss() } else { scanned = nil }
                }
            }
            if let scanned {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save(scanned) }
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
        .alert("Scan impossible", isPresented: .constant(failure != nil)) {
            Button("Fermer") {
                failure = nil
                dismiss()
            }
        } message: {
            Text(failure ?? "")
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    @ViewBuilder
    private func summary(for room: ScannedRoom) -> some View {
        VStack(spacing: 0) {
            RoomMaquetteView(room: room)
                .frame(maxWidth: .infinity)
                .frame(height: 320)

            Form {
                Section("Nom de la pièce") {
                    TextField("Salon", text: $name)
                }
                Section {
                    Text(summaryLine(for: room))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Résultat du scan")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func summaryLine(for room: ScannedRoom) -> String {
        let walls = room.walls.count
        let pieces = room.furniture.count
        let wallText = walls == 1 ? "1 mur" : "\(walls) murs"
        let pieceText = pieces == 1 ? "1 meuble reconnu" : "\(pieces) meubles reconnus"
        return "\(wallText), \(pieceText)"
    }

    private func save(_ room: ScannedRoom) {
        do {
            try store.save(room, named: trimmedName)
            onSaved()
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }
}
