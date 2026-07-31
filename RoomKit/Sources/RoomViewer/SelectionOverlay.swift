#if os(iOS)
import RoomModel
import SwiftUI

/// Fiche du meuble sélectionné : ce que la reconnaissance en a dit.
public struct SelectionOverlay: View {
    private let piece: FurniturePiece
    private let onDismiss: () -> Void

    public init(piece: FurniturePiece, onDismiss: @escaping () -> Void) {
        self.piece = piece
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(piece.category.displayName)
                    .font(.headline)
                Text(piece.dimensionsLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !piece.confidence.isCertain {
                    Label("Reconnaissance incertaine", systemImage: "questionmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Fermer la fiche")
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }
}
#endif
