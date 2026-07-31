#if os(iOS)
import RoomModel
import SwiftUI

/// Liste des meubles reconnus, groupés et comptés. C'est la lecture la plus
/// directe du résultat de la reconnaissance, et le moyen de retrouver un
/// meuble sans le chercher à l'œil dans la maquette.
public struct InventoryPanel: View {
    private let groups: [FurnitureInventory.Group]
    private let selection: UUID?
    private let onSelect: (UUID) -> Void

    public init(
        room: ScannedRoom, selection: UUID?, onSelect: @escaping (UUID) -> Void
    ) {
        self.groups = FurnitureInventory.groups(for: room)
        self.selection = selection
        self.onSelect = onSelect
    }

    public var body: some View {
        List {
            Section {
                if groups.isEmpty {
                    Text("Aucun meuble reconnu dans cette pièce.")
                        .foregroundStyle(.secondary)
                }
                ForEach(groups) { group in
                    ForEach(group.pieces) { piece in
                        Button { onSelect(piece.id) } label: { row(for: piece) }
                            .buttonStyle(.plain)
                    }
                }
            } header: {
                Text(totalCount == 1 ? "1 meuble reconnu" : "\(totalCount) meubles reconnus")
            }
        }
        .listStyle(.plain)
    }

    private var totalCount: Int { groups.reduce(0) { $0 + $1.count } }

    private func row(for piece: FurniturePiece) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(FurniturePalette.color(for: piece.category)))
                .frame(width: 14, height: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(piece.category.displayName)
                Text(piece.dimensionsLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !piece.confidence.isCertain {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Reconnaissance incertaine")
            }
            if piece.id == selection {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
    }
}
#endif
