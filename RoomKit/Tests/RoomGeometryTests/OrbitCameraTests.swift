import Testing
import simd
@testable import RoomGeometry

private func approximatelyEqual(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Bool {
    simd_length(a - b) < 0.001
}

@Test func cameraSitsBehindTheTargetAtZeroAzimuth() {
    let camera = OrbitCamera(target: .zero, distance: 5, azimuth: 0, elevation: 0)

    // L'élévation demandée est ramenée à sa borne basse : la caméra reste
    // légèrement au-dessus du sol, jamais dessous.
    #expect(camera.elevation == OrbitCamera.minElevation)
    #expect(camera.position.x == 0)
    #expect(camera.position.y > 0)
    #expect(abs(simd_length(camera.position) - 5) < 0.001)
}

@Test func cameraStaysAtTheRequestedDistanceWhateverTheAngle() {
    let azimuths: [Float] = [0, Float.pi / 3, -2.1]
    let elevations: [Float] = [0.2, 0.9, 1.4]

    for azimuth in azimuths {
        for elevation in elevations {
            let camera = OrbitCamera(
                target: [1, 0, -2], distance: 6, azimuth: azimuth, elevation: elevation)
            #expect(abs(simd_length(camera.position - camera.target) - 6) < 0.001)
        }
    }
}

@Test func cameraRisesAboveTheTargetAsElevationGrows() {
    var camera = OrbitCamera(target: .zero, distance: 5, azimuth: 0, elevation: 0)
    camera.orbit(deltaAzimuth: 0, deltaElevation: .pi / 4)
    #expect(camera.position.y > 3)
    #expect(abs(simd_length(camera.position) - 5) < 0.001)
}

@Test func elevationIsClampedToStayAboveTheFloorAndBelowTheZenith() {
    var camera = OrbitCamera(target: .zero, distance: 5, azimuth: 0, elevation: 0.5)
    camera.orbit(deltaAzimuth: 0, deltaElevation: -10)
    #expect(camera.elevation == OrbitCamera.minElevation)

    camera.orbit(deltaAzimuth: 0, deltaElevation: 10)
    #expect(camera.elevation == OrbitCamera.maxElevation)
}

@Test func azimuthWrapsInsteadOfGrowingWithoutBound() {
    var camera = OrbitCamera(target: .zero, distance: 5, azimuth: 0, elevation: 0.5)
    camera.orbit(deltaAzimuth: 3 * .pi, deltaElevation: 0)
    #expect(camera.azimuth >= -Float.pi && camera.azimuth <= Float.pi)
}

@Test func zoomIsMultiplicativeAndClamped() {
    var camera = OrbitCamera(target: .zero, distance: 5, azimuth: 0, elevation: 0.5)
    camera.zoom(factor: 0.5)
    #expect(abs(camera.distance - 2.5) < 0.001)

    camera.zoom(factor: 0.0001)
    #expect(camera.distance == OrbitCamera.minDistance)

    camera.zoom(factor: 10_000)
    #expect(camera.distance == OrbitCamera.maxDistance)
}

@Test func panMovesTheTargetInTheCameraGroundFrame() {
    var camera = OrbitCamera(target: .zero, distance: 5, azimuth: 0, elevation: 0.5)
    camera.pan(right: 1, forward: 0)

    #expect(abs(camera.target.x - 1) < 0.001)
    #expect(camera.target.y == 0)
    #expect(abs(camera.target.z) < 0.001)
}

@Test func topDownLooksStraightDownWithoutChangingDistance() {
    var camera = OrbitCamera(target: [1, 0, 2], distance: 7, azimuth: 1, elevation: 0.3)
    camera.topDown()

    #expect(camera.elevation == OrbitCamera.maxElevation)
    #expect(camera.distance == 7)
    #expect(camera.target == SIMD3<Float>(1, 0, 2))
}
