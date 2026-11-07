#if os(iOS)
import RoomGeometry
import RoomModel
import SwiftUI
import simd

/// Dimensioned top-down plan: walls with their lengths, chain dimensions to
/// every opening, and optionally the detected furniture. Pinch to zoom,
/// drag to move.
public struct FloorPlanView: View {
    private let plan: FloorPlan

    @State private var showsFurniture = false
    @State private var isLegendPresented = false
    @State private var zoom: CGFloat = 1
    @State private var zoomStart: CGFloat?
    @State private var offset: CGSize = .zero
    @State private var offsetStart: CGSize?

    /// Room left around the walls for the two rows of dimensions.
    static let margin: Float = 1.0

    public init(room: ScannedRoom) {
        plan = FloorPlan(room: room)
    }

    public var body: some View {
        VStack(spacing: 0) {
            Canvas { context, size in
                FloorPlanRenderer(plan: plan, showsFurniture: showsFurniture)
                    .draw(in: &context, size: size, zoom: zoom, offset: offset)
            }
            .background(Color.white)
            .contentShape(Rectangle())
            .gesture(panGesture)
            .simultaneousGesture(zoomGesture)
            .onTapGesture(count: 2) {
                withAnimation(.snappy) { zoom = 1; offset = .zero }
            }

            summaryBar
        }
        .sheet(isPresented: $isLegendPresented) { legend }
    }

    private var summaryBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(planLength(plan.area)) m² · périmètre \(planLength(plan.perimeter)) m · "
                     + "hauteur \(planLength(plan.ceilingHeight)) m")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
            }
            HStack {
                Toggle(isOn: $showsFurniture.animation(.snappy)) {
                    Label("Meubles", systemImage: "sofa")
                }
                .toggleStyle(.button)
                Spacer()
                Button {
                    isLegendPresented = true
                } label: {
                    Label("Légende", systemImage: "list.bullet")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var legend: some View {
        NavigationStack {
            List {
                Section("Pièce") {
                    LabeledContent("Surface au sol", value: "\(planLength(plan.area)) m²")
                    LabeledContent("Périmètre", value: "\(planLength(plan.perimeter)) m")
                    LabeledContent("Hauteur sous plafond", value: "\(planLength(plan.ceilingHeight)) m")
                }
                Section("Ouvertures (largeur × hauteur)") {
                    ForEach(plan.openings, id: \.label) { o in
                        LabeledContent {
                            Text("\(planLength(o.width)) × \(planLength(o.height))"
                                 + (o.kind == .window ? " · allège \(planLength(o.sill))" : ""))
                        } label: {
                            Label {
                                Text("\(o.label)  \(o.kind.displayName)")
                            } icon: {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(FloorPlanRenderer.color(for: o.kind))
                                    .frame(width: 12, height: 12)
                            }
                        }
                    }
                }
                if showsFurniture {
                    Section("Meubles détectés (L × P × H)") {
                        ForEach(plan.furniture, id: \.number) { piece in
                            LabeledContent {
                                Text("\(planLength(piece.footprint.x)) × \(planLength(piece.footprint.y))"
                                     + " × \(planLength(piece.height))")
                            } label: {
                                Text("\(piece.number). \(piece.category.displayName)"
                                     + (piece.confidence.isCertain ? "" : " (incertain)"))
                            }
                        }
                    }
                }
                Section {
                    Text("Cotes grises : distances d'un angle à une ouverture le long du mur. "
                         + "Cote noire : mur entier. Mesures en mètres, à quelques centimètres près.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Légende")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Gestures

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let start = offsetStart ?? offset
                if offsetStart == nil { offsetStart = start }
                offset = CGSize(width: start.width + value.translation.width,
                                height: start.height + value.translation.height)
            }
            .onEnded { _ in offsetStart = nil }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = zoomStart ?? zoom
                if zoomStart == nil { zoomStart = start }
                zoom = min(max(start * value.magnification, 0.5), 6)
            }
            .onEnded { _ in zoomStart = nil }
    }
}

/// Draws a `FloorPlan` into a SwiftUI canvas.
struct FloorPlanRenderer {
    let plan: FloorPlan
    let showsFurniture: Bool

    static func color(for kind: OpeningKind) -> Color {
        switch kind {
        case .door: Color(red: 0.85, green: 0.51, blue: 0.17)
        case .window: Color(red: 0.17, green: 0.70, blue: 0.85)
        case .opening: Color(white: 0.56)
        }
    }

    private static let ink = Color(white: 0.11)
    private static let grey = Color(white: 0.43)
    private static let furnitureFill = Color(red: 0.29, green: 0.56, blue: 0.85)

    func draw(in context: inout GraphicsContext, size: CGSize, zoom: CGFloat, offset: CGSize) {
        guard !plan.walls.isEmpty else { return }
        let margin = FloorPlanView.margin
        let extent = plan.size + SIMD2(repeating: 2 * margin)
        let fit = min(size.width / CGFloat(extent.x), size.height / CGFloat(extent.y))
        let scale = fit * zoom
        let originX = (size.width - CGFloat(extent.x) * scale) / 2 + offset.width
        let originY = (size.height - CGFloat(extent.y) * scale) / 2 + offset.height
        func P(_ p: SIMD2<Float>) -> CGPoint {
            CGPoint(x: originX + CGFloat(p.x + margin) * scale, y: originY + CGFloat(p.y + margin) * scale)
        }

        // Floor.
        var floor = Path()
        floor.addLines(plan.walls.map { P($0.start) })
        floor.closeSubpath()
        context.fill(floor, with: .color(Color(white: 0.96)))

        if showsFurniture { drawFurniture(in: &context, P: P) }

        let wallWidth = max(4, 0.08 * scale)
        for wall in plan.walls {
            // Wall stretches between openings.
            let cuts = wall.cuts
            for i in stride(from: 0, to: cuts.count - 1, by: 2) {
                var path = Path()
                path.move(to: P(wall.point(at: cuts[i])))
                path.addLine(to: P(wall.point(at: cuts[i + 1])))
                context.stroke(path, with: .color(Self.ink),
                               style: StrokeStyle(lineWidth: wallWidth, lineCap: .square))
            }
            for o in wall.openings {
                var path = Path()
                path.move(to: P(wall.point(at: o.start)))
                path.addLine(to: P(wall.point(at: o.end)))
                context.stroke(path, with: .color(Self.color(for: o.kind)),
                               style: StrokeStyle(lineWidth: wallWidth * 0.7,
                                                  dash: o.kind == .opening ? [4, 3] : []))
            }

            // Dimensions: chain (grey) close to the wall, total (black) further out.
            let hasOpenings = !wall.openings.isEmpty
            if hasOpenings {
                for (a, b) in zip(cuts, cuts.dropFirst()) where b - a > 0.04 {
                    // A stretch too short on screen keeps its line, not its text.
                    let fits = CGFloat(b - a) * scale > 26
                    dimension(from: wall.point(at: a), to: wall.point(at: b), wall: wall, offset: 0.3,
                              label: fits ? planLength(b - a) : nil, font: .system(size: 9),
                              color: Self.grey, in: &context, P: P)
                }
            }
            dimension(from: wall.start, to: wall.end, wall: wall, offset: hasOpenings ? 0.65 : 0.35,
                      label: planLength(wall.length), font: .system(size: 11, weight: .semibold),
                      color: Self.ink, in: &context, P: P)
        }

        for (label, point, kind) in openingLabels(minimumGap: Float(26 / scale)) {
            context.draw(Text(label).font(.caption2.bold()).foregroundStyle(Self.color(for: kind)),
                         at: P(point))
        }
    }

    /// Opening labels inside the room, pushed further in when two would
    /// overlap (doors and passages meeting at a corner). Labels of horizontal
    /// walls are placed first, so vertical ones step aside sideways.
    private func openingLabels(minimumGap: Float) -> [(String, SIMD2<Float>, OpeningKind)] {
        let walls = plan.walls.sorted { abs($0.direction.x) > abs($1.direction.x) }
        var placed: [(String, SIMD2<Float>, OpeningKind)] = []
        for wall in walls {
            let inward = -plan.outwardNormal(of: wall)
            for o in wall.openings {
                let base = wall.point(at: (o.start + o.end) / 2)
                var depth: Float = 0.3
                var point = base + inward * depth
                while depth < 1.5, placed.contains(where: { simd_distance($0.1, point) < minimumGap }) {
                    depth += 0.12
                    point = base + inward * depth
                }
                placed.append((o.label, point, o.kind))
            }
        }
        return placed
    }

    private func drawFurniture(in context: inout GraphicsContext, P: (SIMD2<Float>) -> CGPoint) {
        var badges: [CGPoint] = []
        for piece in plan.furniture {
            var path = Path()
            path.addLines(piece.corners.map(P))
            path.closeSubpath()
            let opacity: Double = switch piece.confidence { case .high: 0.5; case .medium: 0.38; case .low: 0.25 }
            context.fill(path, with: .color(Self.furnitureFill.opacity(opacity)))
            context.stroke(path, with: .color(Self.furnitureFill), lineWidth: 1)
            // Stacked pieces (a TV on its cabinet) would hide each other's number.
            var center = P(piece.center)
            while badges.contains(where: { hypot($0.x - center.x, $0.y - center.y) < 20 }) {
                center.y += 20
            }
            badges.append(center)
            let badge = Path(ellipseIn: CGRect(x: center.x - 9, y: center.y - 9, width: 18, height: 18))
            context.fill(badge, with: .color(.white))
            context.stroke(badge, with: .color(Self.furnitureFill), lineWidth: 1)
            context.draw(Text("\(piece.number)").font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Self.furnitureFill), at: center)
        }
    }

    /// A dimension line parallel to the wall, outside the room, with ticks,
    /// extension lines back to the wall and its length written along it.
    private func dimension(
        from a: SIMD2<Float>, to b: SIMD2<Float>, wall: FloorPlan.WallSegment, offset: Float,
        label: String?, font: Font, color: Color,
        in context: inout GraphicsContext, P: (SIMD2<Float>) -> CGPoint
    ) {
        let n = plan.outwardNormal(of: wall)
        let a2 = a + n * offset, b2 = b + n * offset
        var line = Path()
        line.move(to: P(a2))
        line.addLine(to: P(b2))
        context.stroke(line, with: .color(color), lineWidth: 0.8)

        let d = wall.direction
        for end in [a2, b2] {
            var tick = Path()
            tick.move(to: P(end - (d + n) * 0.06))
            tick.addLine(to: P(end + (d + n) * 0.06))
            context.stroke(tick, with: .color(color), lineWidth: 1.2)
        }
        for (wallPoint, dimPoint) in [(a, a2), (b, b2)] {
            var ext = Path()
            ext.move(to: P(wallPoint + n * 0.08))
            ext.addLine(to: P(dimPoint))
            context.stroke(ext, with: .color(Color(white: 0.78)), lineWidth: 0.6)
        }

        guard let label else { return }
        // Text sits a fixed distance in points outside the line, whatever the zoom.
        let base = P((a2 + b2) / 2)
        let mid = CGPoint(x: base.x + CGFloat(n.x) * 9, y: base.y + CGFloat(n.y) * 9)
        var angle = atan2(Double(d.y), Double(d.x))
        if angle > .pi / 2 { angle -= .pi }
        if angle <= -.pi / 2 { angle += .pi }
        var text = context
        text.translateBy(x: mid.x, y: mid.y)
        text.rotate(by: .radians(angle))
        text.draw(Text(label).font(font).foregroundStyle(color), at: .zero)
    }
}
#endif
