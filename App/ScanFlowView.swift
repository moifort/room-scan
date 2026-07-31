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
            .overlay(alignment: .top) { captureHint }
            .overlay { processingOverlay }
            .navigationTitle("Scan de la pièce")
            .navigationBarTitleDisplayMode(.inline)
    }

    /// Consigne et diagnostic en haut : le bas de l'écran appartient à RoomPlan,
    /// qui y affiche l'aperçu 3D du scan en cours.
    @ViewBuilder
    private var captureHint: some View {
        if controller.isScanning {
            Text("Parcourez la pièce en visant les murs, puis touchez Terminer.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.black.opacity(0.45), in: Capsule())
                .padding(.horizontal, 24)
                .padding(.top, 8)
        } else if controller.phase != .processing {
            // Tant que la session n'a pas démarré, dire où en est l'app plutôt
            // que de laisser un écran noir sans explication.
            VStack(alignment: .leading, spacing: 4) {
                Text("Préparation du scan…")
                    .font(.headline)
                ForEach(controller.diagnostics, id: \.self) { line in
                    Text(line)
                        .font(.caption.monospaced())
                        .opacity(0.85)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.black.opacity(0.55))
        }
    }

    @ViewBuilder
    private var processingOverlay: some View {
        if controller.phase == .processing {
            ProgressView("Analyse de la pièce…")
                .tint(.white)
                .foregroundStyle(.white)
                .padding(24)
                .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Résultat

    @ViewBuilder
    private func summary(for room: ScannedRoom) -> some View {
        VStack(spacing: 0) {
            // La maquette prend tout l'espace restant : c'est elle qu'on vient
            // regarder, le nommage tient en deux lignes.
            RoomMaquetteView(room: room)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                TextField("Nom de la pièce", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)

                Text(summaryLine(for: room))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(.bar)
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
        } else if controller.isScanning {
            // C'est l'arrêt de la session qui déclenche l'analyse et produit la
            // pièce : sans ce bouton, un scan ne se conclut jamais.
            ToolbarItem(placement: .confirmationAction) {
                Button("Terminer") { controller.finish() }
                    .fontWeight(.semibold)
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
