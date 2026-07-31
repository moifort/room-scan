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
    @State private var controller = RoomCaptureController()
    @State private var name = ""
    @State private var failure: String?

    var body: some View {
        Group {
            if let scanned = controller.scannedRoom {
                summary(for: scanned)
            } else {
                capture
            }
        }
        .toolbar { toolbarContent }
        .alert("Scan impossible", isPresented: .constant(failure != nil)) {
            Button("Fermer") {
                failure = nil
                dismiss()
            }
        } message: {
            Text(failure ?? "")
        }
        .onChange(of: controller.phase) { _, phase in
            if case .failed(let message) = phase { failure = message }
        }
    }

    // MARK: - Scan

    private var capture: some View {
        RoomCaptureScreen(controller: controller)
            .ignoresSafeArea()
            .overlay(alignment: .bottom) { captureFooter }
            .navigationTitle("Scan de la pièce")
            .navigationBarTitleDisplayMode(.inline)
    }

    /// Sans bouton de fin, un scan ne se conclut jamais : c'est l'arrêt de la
    /// session qui déclenche le post-traitement et produit la pièce.
    @ViewBuilder
    private var captureFooter: some View {
        VStack(spacing: 12) {
            if controller.isScanning {
                Text("Parcourez la pièce en visant les murs, puis touchez Terminer.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)

                Button {
                    controller.finish()
                } label: {
                    Text("Terminer le scan")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
            } else if controller.phase == .processing {
                ProgressView("Analyse de la pièce…")
                    .tint(.white)
                    .foregroundStyle(.white)
            } else {
                // Tant que la session n'a pas démarré, dire où en est l'app
                // plutôt que de laisser un écran noir sans explication.
                VStack(alignment: .leading, spacing: 4) {
                    Text("Préparation du scan…")
                        .font(.headline)
                        .foregroundStyle(.white)
                    ForEach(controller.diagnostics, id: \.self) { line in
                        Text(line)
                            .font(.caption.monospaced())
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .background(.black.opacity(0.55))
    }

    // MARK: - Résultat

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

    // MARK: - Barre d'outils

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Annuler") {
                controller.cancel()
                dismiss()
            }
        }
        if let scanned = controller.scannedRoom {
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") { save(scanned) }
                    .disabled(trimmedName.isEmpty)
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
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
