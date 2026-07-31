import Testing
import simd
import RoomModel
@testable import RoomGeometry

private let viewSize = SIMD2<Float>(402, 874)
private let fieldOfView = Float.pi / 3

private func demoCamera() -> OrbitCamera {
    FrameFitting.initialCamera(
        for: .demoLivingRoom, verticalFieldOfView: fieldOfView,
        aspectRatio: viewSize.x / viewSize.y)
}

@Test func rayFromTheCentreOfTheScreenAimsAtTheTarget() {
    let camera = demoCamera()
    let ray = FurniturePicking.ray(
        at: viewSize / 2, viewSize: viewSize, camera: camera,
        verticalFieldOfView: fieldOfView)

    let toTarget = simd_normalize(camera.target - camera.position)
    #expect(simd_length(ray.direction - toTarget) < 0.001)
    #expect(ray.origin == camera.position)
}

@Test func rayDirectionIsAlwaysNormalised() {
    let camera = demoCamera()
    for point in [SIMD2<Float>(0, 0), [402, 874], [10, 800], [390, 30]] {
        let ray = FurniturePicking.ray(
            at: point, viewSize: viewSize, camera: camera,
            verticalFieldOfView: fieldOfView)
        #expect(abs(simd_length(ray.direction) - 1) < 0.001)
    }
}

@Test func rayThroughTheScreenCentreHitsAFurniturePieceOnTheTarget() {
    // Un meuble posé exactement au point visé doit être touché par le rayon
    // central, quelle que soit l'orientation de la caméra autour de lui.
    let piece = FurniturePiece(
        category: .table, center: [0, 0.25, 0],
        footprint: [1, 1], height: 0.5, yaw: 0, confidence: .high)
    let camera = OrbitCamera(
        target: [0, 0.25, 0], distance: 4, azimuth: 0.7, elevation: 0.5)

    let hit = FurniturePicking.pick(
        at: viewSize / 2, viewSize: viewSize, camera: camera,
        verticalFieldOfView: fieldOfView, furniture: [piece])

    #expect(hit == piece.id)
}

@Test func aRayPointingAwayFromEverythingHitsNothing() {
    let camera = OrbitCamera(
        target: [0, 0.25, 0], distance: 4, azimuth: 0, elevation: 0.5)
    let piece = FurniturePiece(
        category: .table, center: [0, 0.25, 0],
        footprint: [0.4, 0.4], height: 0.5, yaw: 0, confidence: .high)

    // Coin supérieur gauche : le rayon part loin du meuble minuscule visé.
    let hit = FurniturePicking.pick(
        at: [2, 2], viewSize: viewSize, camera: camera,
        verticalFieldOfView: fieldOfView, furniture: [piece])

    #expect(hit == nil)
}

@Test func theNearestPieceWinsWhenTwoAreLinedUp() {
    let camera = OrbitCamera(target: [0, 0.5, 0], distance: 6, azimuth: 0, elevation: 0.08)

    // Deux meubles alignés sur l'axe de visée, l'un devant l'autre.
    let near = FurniturePiece(
        category: .chair, center: [0, 0.5, 2],
        footprint: [1, 1], height: 1, yaw: 0, confidence: .high)
    let far = FurniturePiece(
        category: .sofa, center: [0, 0.5, -2],
        footprint: [1, 1], height: 1, yaw: 0, confidence: .high)

    let hit = FurniturePicking.pick(
        at: viewSize / 2, viewSize: viewSize, camera: camera,
        verticalFieldOfView: fieldOfView, furniture: [far, near])

    #expect(hit == near.id)
}

@Test func rotationOfAPieceIsTakenIntoAccount() {
    // Boîte très allongée, tournée d'un quart de tour : un rayon vertical qui
    // manquerait la boîte non tournée doit désormais la toucher.
    let piece = FurniturePiece(
        category: .table, center: [0, 0.25, 0],
        footprint: [3, 0.2], height: 0.5, yaw: .pi / 2, confidence: .high)

    let origin = SIMD3<Float>(0, 5, 1.2)
    let direction = SIMD3<Float>(0, -1, 0)

    #expect(FurniturePicking.intersection(
        origin: origin, direction: direction, piece: piece) != nil)

    let straight = FurniturePiece(
        category: .table, center: [0, 0.25, 0],
        footprint: [3, 0.2], height: 0.5, yaw: 0, confidence: .high)
    #expect(FurniturePicking.intersection(
        origin: origin, direction: direction, piece: straight) == nil)
}

@Test func aPieceBehindTheEyeIsNotPicked() {
    let piece = FurniturePiece(
        category: .table, center: [0, 0.25, 0],
        footprint: [1, 1], height: 0.5, yaw: 0, confidence: .high)

    // Rayon partant au-delà du meuble et s'en éloignant.
    let hit = FurniturePicking.intersection(
        origin: [0, 0.25, 5], direction: [0, 0, 1], piece: piece)
    #expect(hit == nil)
}
