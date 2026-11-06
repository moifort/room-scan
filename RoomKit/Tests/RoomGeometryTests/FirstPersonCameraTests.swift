import RoomModel
import Testing
import simd
@testable import RoomGeometry

private let square = FloorOutline(points: [[-2, -2], [2, -2], [2, 2], [-2, 2]])

@Test func eyesStartAtOneSixtyAboveFloor() {
    let camera = FirstPersonCamera(floorPoint: [1, 2], floorHeight: -1.4)
    #expect(simd_length(camera.position - [1, 0.2, 2]) < 1e-5)
    #expect(abs(simd_length(camera.forward - [0, 0, -1])) < 1e-5)
}

@Test func pitchIsClamped() {
    var camera = FirstPersonCamera(floorPoint: .zero, floorHeight: 0)
    camera.look(deltaYaw: 0, deltaPitch: 5)
    #expect(camera.pitch == FirstPersonCamera.maxPitch)
    camera.look(deltaYaw: 0, deltaPitch: -10)
    #expect(camera.pitch == -FirstPersonCamera.maxPitch)
}

@Test func walkInsideGoesThere() {
    var camera = FirstPersonCamera(floorPoint: .zero, floorHeight: 0)
    camera.walk(to: [1, -1], within: square)
    #expect(camera.position.x == 1)
    #expect(camera.position.z == -1)
    #expect(camera.position.y == FirstPersonCamera.eyeHeight)
}

@Test func walkStaysInsideOutline() {
    var camera = FirstPersonCamera(floorPoint: .zero, floorHeight: 0)
    camera.walk(to: [6, 0], within: square)
    #expect(abs(camera.position.x - 2) < 0.01)
    #expect(square.contains(SIMD2(camera.position.x - 0.001, camera.position.z)))
}

@Test func tapBelowHorizonHitsFloorAhead() throws {
    let camera = FirstPersonCamera(floorPoint: .zero, floorHeight: 0)
    let hit = try #require(camera.floorHit(
        normalizedScreenPoint: [0, -0.5], verticalFieldOfView: .pi / 3, aspectRatio: 0.46))
    #expect(abs(hit.x) < 1e-4)
    #expect(hit.y < 0)  // ahead is −Z
    // tan(30°)·0.5 ≈ 0.289 down per metre ahead: 1.6 / 0.289 ≈ 5.5 m.
    #expect(abs(-hit.y - 1.6 / (tan(Float.pi / 6) * 0.5)) < 0.05)
}

@Test func tapAboveHorizonHitsNothing() {
    let camera = FirstPersonCamera(floorPoint: .zero, floorHeight: 0)
    #expect(camera.floorHit(normalizedScreenPoint: [0, 0.3], verticalFieldOfView: .pi / 3,
                            aspectRatio: 0.46) == nil)
}

@Test func floorHeightIsWallBase() {
    let room = ScannedRoom(
        walls: [Wall(center: [0, -0.37, 0], width: 4, height: 2.6, yaw: 0)],
        openings: [], furniture: [], floor: square)
    #expect(abs(room.floorHeight - (-1.67)) < 1e-4)
}
