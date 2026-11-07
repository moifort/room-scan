import Foundation
import RoomModel
import simd

/// A dimensioned top-down plan of a scanned room, in plan metres: x to the
/// right, y downwards, origin at the top-left corner of the room's bounds.
/// The first scanned wall is turned horizontal so that the plan reads square.
/// Pure geometry: the view only draws it.
public struct FloorPlan: Sendable {
    public struct PlacedOpening: Sendable, Equatable {
        public var kind: OpeningKind
        public var label: String
        /// Distances from the wall's start corner, along the wall.
        public var start: Float
        public var end: Float
        public var height: Float
        /// Height of the bottom edge above the floor (a window's sill).
        public var sill: Float
        public var width: Float { end - start }
    }

    public struct WallSegment: Sendable, Equatable {
        public var start: SIMD2<Float>
        public var end: SIMD2<Float>
        public var openings: [PlacedOpening]
        public var length: Float { simd_distance(start, end) }
        public var direction: SIMD2<Float> { simd_normalize(end - start) }

        /// Boundaries along the wall: corner, opening edges, corner. The
        /// stretches between consecutive cuts are the chain dimensions.
        public var cuts: [Float] {
            var values: [Float] = [0]
            for o in openings { values += [max(0, o.start), min(length, o.end)] }
            values.append(length)
            return values
        }

        public func point(at t: Float) -> SIMD2<Float> { start + direction * t }
    }

    public struct PlacedFurniture: Sendable, Equatable {
        public var number: Int
        public var category: FurnitureCategory
        public var corners: [SIMD2<Float>]
        public var center: SIMD2<Float>
        public var footprint: SIMD2<Float>
        public var height: Float
        public var confidence: DetectionConfidence
    }

    public let walls: [WallSegment]
    public let furniture: [PlacedFurniture]
    public let area: Float
    public let perimeter: Float
    public let ceilingHeight: Float
    /// Size of the room's bounds.
    public let size: SIMD2<Float>
    /// +1 when the wall polygon runs counter-clockwise in plan coordinates.
    let orientation: Float

    public var openings: [PlacedOpening] { walls.flatMap(\.openings) }

    /// Outward normal of a wall, pointing away from the room.
    public func outwardNormal(of wall: WallSegment) -> SIMD2<Float> {
        let d = wall.direction
        return SIMD2(d.y, -d.x) * orientation
    }

    public init(room: ScannedRoom) {
        let reference = room.walls.first?.yaw ?? 0
        let c = cos(reference), s = sin(reference)
        func rotate(_ p: SIMD2<Float>) -> SIMD2<Float> {
            SIMD2(p.x * c - p.y * s, p.x * s + p.y * c)
        }

        // Wall end points, rotated so the first wall runs along x.
        var pieces: [(a: SIMD2<Float>, b: SIMD2<Float>, wall: Wall)] = room.walls.map { wall in
            let half = SIMD2(cos(wall.yaw), -sin(wall.yaw)) * (wall.width / 2)
            return (rotate(wall.groundPosition - half), rotate(wall.groundPosition + half), wall)
        }

        // Chain the walls into a loop, nearest end to nearest end.
        var ordered: [(a: SIMD2<Float>, b: SIMD2<Float>, wall: Wall)] = []
        if !pieces.isEmpty { ordered.append(pieces.removeFirst()) }
        while !pieces.isEmpty, let end = ordered.last?.b {
            let index = pieces.indices.min { i, j in
                min(simd_distance(end, pieces[i].a), simd_distance(end, pieces[i].b))
                    < min(simd_distance(end, pieces[j].a), simd_distance(end, pieces[j].b))
            }!
            var next = pieces.remove(at: index)
            if simd_distance(end, next.b) < simd_distance(end, next.a) { swap(&next.a, &next.b) }
            ordered.append(next)
        }

        let all = ordered.flatMap { [$0.a, $0.b] }
            + room.furniture.map { rotate($0.groundPosition) }
        let low = all.reduce(SIMD2(repeating: Float.greatestFiniteMagnitude), simd_min)
        let high = all.reduce(SIMD2(repeating: -Float.greatestFiniteMagnitude), simd_max)
        let origin = all.isEmpty ? .zero : low
        size = all.isEmpty ? .zero : high - low

        let corners = ordered.map { $0.a - origin }
        var signedArea: Float = 0
        for i in corners.indices {
            let p = corners[i], q = corners[(i + 1) % corners.count]
            signedArea += p.x * q.y - q.x * p.y
        }
        signedArea /= 2
        orientation = signedArea >= 0 ? 1 : -1
        area = abs(signedArea)
        perimeter = ordered.reduce(0) { $0 + simd_distance($1.a, $1.b) }
        ceilingHeight = room.ceilingHeight

        // Openings go on the wall that contains them.
        var segments = ordered.map {
            WallSegment(start: $0.a - origin, end: $0.b - origin, openings: [])
        }
        let floor = room.floorHeight
        for opening in room.openings {
            let p = rotate(SIMD2(opening.center.x, opening.center.z)) - origin
            var best: (index: Int, t: Float, distance: Float)?
            for (i, segment) in segments.enumerated() {
                let d = segment.direction
                let v = p - segment.start
                let t = simd_dot(v, d)
                let distance = abs(v.x * d.y - v.y * d.x)
                guard t >= -0.05, t <= segment.length + 0.05 else { continue }
                if best == nil || distance < best!.distance { best = (i, t, distance) }
            }
            guard let best else { continue }
            segments[best.index].openings.append(PlacedOpening(
                kind: opening.kind, label: "",
                start: best.t - opening.width / 2, end: best.t + opening.width / 2,
                height: opening.height,
                sill: max(opening.center.y - opening.height / 2 - floor, 0)))
        }
        // Number them around the room: P1, P2… for doors, F for windows, O for openings.
        var counters: [OpeningKind: Int] = [:]
        for i in segments.indices {
            segments[i].openings.sort { $0.start < $1.start }
            for j in segments[i].openings.indices {
                let kind = segments[i].openings[j].kind
                counters[kind, default: 0] += 1
                let prefix = switch kind { case .door: "P"; case .window: "F"; case .opening: "O" }
                segments[i].openings[j].label = "\(prefix)\(counters[kind]!)"
            }
        }
        walls = segments

        furniture = room.furniture
            .sorted { ($0.category.displayName, -$0.footprint.x) < ($1.category.displayName, -$1.footprint.x) }
            .enumerated().map { index, piece in
                let center = rotate(piece.groundPosition) - origin
                let yaw = piece.yaw - reference
                let u = SIMD2(cos(yaw), -sin(yaw)), v = SIMD2(-u.y, u.x)
                let hw = piece.footprint.x / 2, hd = piece.footprint.y / 2
                let corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)].map { (sx, sy) in
                    center + u * (Float(sx) * hw) + v * (Float(sy) * hd)
                }
                return PlacedFurniture(
                    number: index + 1, category: piece.category, corners: corners, center: center,
                    footprint: piece.footprint, height: piece.height, confidence: piece.confidence)
            }
    }
}

/// Metres with a French decimal comma: 3,09.
public func planLength(_ metres: Float) -> String {
    String(format: "%.2f", metres).replacingOccurrences(of: ".", with: ",")
}
