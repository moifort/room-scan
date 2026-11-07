import Foundation
import RoomModel
import Testing
import simd
@testable import RoomGeometry

private func salon() throws -> ScannedRoom {
    let url = try #require(Bundle.module.url(forResource: "salon-scan", withExtension: "json",
                                             subdirectory: "Fixtures"))
    return try JSONDecoder().decode(ScannedRoom.self, from: Data(contentsOf: url))
}

/// Same figures as the plan drawn and checked by hand on 2026-11-06.
@Test func salonPlanMatchesTheValidatedPlan() throws {
    let plan = FloorPlan(room: try salon())
    #expect(abs(plan.area - 37.17) < 0.01)
    #expect(abs(plan.perimeter - 27.46) < 0.01)
    #expect(plan.walls.map { planLength($0.length) } == ["7,39", "3,20", "3,09", "3,13", "4,31", "6,33"])
    #expect(plan.openings.count == 7)
    let top = plan.walls[0]
    let chain = zip(top.cuts, top.cuts.dropFirst()).map { planLength($1 - $0) }
    #expect(chain == ["4,90", "1,22", "1,27"])
    #expect(plan.openings.map(\.label).sorted() == ["F1", "O1", "O2", "P1", "P2", "P3", "P4"])
}

@Test func firstWallRunsHorizontally() throws {
    let plan = FloorPlan(room: try salon())
    #expect(abs(plan.walls[0].direction.y) < 1e-4)
}

@Test func outwardNormalsPointAwayFromTheRoom() throws {
    let plan = FloorPlan(room: try salon())
    let center = plan.walls.map(\.start).reduce(.zero, +) / Float(plan.walls.count)
    // The top wall's outside is away from the room's middle.
    let top = plan.walls[0]
    #expect(simd_dot(plan.outwardNormal(of: top), top.point(at: top.length / 2) - center) > 0)
}

@Test func windowSillIsMeasuredFromTheFloor() {
    let plan = FloorPlan(room: .demoLivingRoom)
    let window = plan.openings.first { $0.kind == .window }!
    #expect(abs(window.sill - 0.8) < 0.001)
    #expect(abs(window.width - 1.4) < 0.001)
}

@Test func furnitureIsNumberedAndPlacedInsideThePlan() {
    let plan = FloorPlan(room: .demoLivingRoom)
    #expect(plan.furniture.map(\.number) == Array(1...plan.furniture.count))
    for piece in plan.furniture {
        #expect(piece.center.x >= -0.01 && piece.center.x <= plan.size.x + 0.01)
        #expect(piece.center.y >= -0.01 && piece.center.y <= plan.size.y + 0.01)
    }
}

@Test func roomWithoutWallsGivesAnEmptyPlan() {
    let plan = FloorPlan(room: ScannedRoom(walls: [], openings: [], furniture: [],
                                           floor: FloorOutline(points: [])))
    #expect(plan.walls.isEmpty)
    #expect(plan.area == 0)
}
