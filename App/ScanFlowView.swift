import RoomCapture
import RoomModel
import RoomStore
import RoomViewer
import SwiftUI

/// Enchaîne le scan, l'habillage, le nommage et l'enregistrement.
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
            if case .failed(let message) = phase {
                controller.discardWorkspace()
                failure = message
            }
        }
    }

    // MARK: - Scan

    private var capture: some View {
        ZStack {
            // RoomPlan's view stays alive (its processing finishes in the
            // background) but is hidden once the dressing pass takes over.
            RoomCaptureScreen(controller: controller)
                .opacity(showsRoomPlanView ? 1 : 0)
            if let recorder = controller.recorder {
                DressingCaptureView(session: controller.arSession, recorder: recorder)
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) { captureHint }
        .overlay(alignment: .bottom) { dressingControls }
        .overlay { processingOverlay }
        .navigationTitle(controller.isDressing ? "Habillage" : "Scan de la pièce")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var showsRoomPlanView: Bool {
        controller.phase == .idle || controller.phase == .scanning
    }

    /// Consigne et diagnostic en haut : le bas de l'écran appartient à RoomPlan,
    /// qui y affiche l'aperçu 3D du scan en cours.
    @ViewBuilder
    private var captureHint: some View {
        if controller.isDressing, let recorder = controller.recorder {
            VStack(spacing: 6) {
                Text("Avancez lentement, approchez-vous de chaque meuble.")
                    .font(.footnote)
                Text("Pièce couverte : \(Int((recorder.coverage * 100).rounded())) % · "
                     + "\(recorder.acceptedCount) photos")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                if recorder.isMovingTooFast {
                    Text("Trop rapide : ralentissez")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.yellow)
                }
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)
            .padding(.top, 8)
        } else if controller.isScanning {
            Text("Parcourez la pièce en visant les murs, puis touchez Terminer.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.black.opacity(0.45), in: Capsule())
                .padding(.horizontal, 24)
                .padding(.top, 8)
        } else if controller.phase == .idle {
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
    private var dressingControls: some View {
        if controller.isDressing {
            HStack(spacing: 12) {
                Button("Passer") { controller.skipDressing() }
                    .buttonStyle(.bordered)
                Button("Terminer l'habillage") { controller.finishDressing() }
                    .buttonStyle(.borderedProminent)
                    .fontWeight(.semibold)
            }
            .controlSize(.large)
            .padding(.bottom, 32)
        }
    }

    @ViewBuilder
    private var processingOverlay: some View {
        switch controller.phase {
        case .waitingForStructure:
            progressCard { ProgressView("Analyse de la pièce…") }
        case .colouring(let progress):
            progressCard {
                ProgressView(value: progress) {
                    Text("Mise en couleurs… \(Int((progress * 100).rounded())) %")
                }
                .frame(width: 220)
            }
        default:
            EmptyView()
        }
    }

    private func progressCard(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .tint(.white)
            .foregroundStyle(.white)
            .padding(24)
            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Résultat

    @ViewBuilder
    private func summary(for room: ScannedRoom) -> some View {
        VStack(spacing: 0) {
            // La maquette prend tout l'espace restant : c'est elle qu'on vient
            // regarder, le nommage tient en deux lignes.
            RoomMaquetteView(room: room, modelURL: controller.modelURL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                TextField("Nom de la pièce", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)

                Text(summaryLine(for: room))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if controller.dressing != nil {
                    Label("Vue réaliste prête", systemImage: "camera.macro")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if controller.dressingFailed {
                    Text("Vue réaliste indisponible : la pièce sera enregistrée sans elle.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
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
            // C'est l'arrêt de la session qui déclenche l'analyse et l'habillage :
            // sans ce bouton, un scan ne se conclut jamais.
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
            try store.save(room, named: trimmedName, modelURL: controller.modelURL,
                           dressing: controller.dressing)
            controller.discardWorkspace()
            onSaved()
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }
}
