import Testing
import simd
import RoomModel
@testable import RoomGeometry

@Test func fittingDistanceGrowsWithTheRoom() {
    let small = FrameFitting.distance(
        boundingRadius: 2, verticalFieldOfView: .pi / 3, aspectRatio: 0.5)
    let large = FrameFitting.distance(
        boundingRadius: 6, verticalFieldOfView: .pi / 3, aspectRatio: 0.5)

    #expect(large > small)
    #expect(small > 2)
}

@Test func narrowerScreensRequireMoreDistance() {
    let wide = FrameFitting.distance(
        boundingRadius: 3, verticalFieldOfView: .pi / 3, aspectRatio: 1.6)
    let narrow = FrameFitting.distance(
        boundingRadius: 3, verticalFieldOfView: .pi / 3, aspectRatio: 0.46)

    #expect(narrow > wide)
}

@Test func initialCameraLooksAtTheMiddleOfTheRoom() {
    let camera = FrameFitting.initialCamera(
        for: .demoLivingRoom, verticalFieldOfView: .pi / 3, aspectRatio: 0.46)

    #expect(abs(camera.target.x) < 0.001)
    #expect(abs(camera.target.z) < 0.001)
    #expect(camera.target.y > 0)
    #expect(camera.distance > 3)
    #expect(camera.elevation > 0.4)
}
