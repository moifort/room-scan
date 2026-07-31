import Testing
import simd
@testable import RoomGeometry

@Test func positionIsReadFromTheTranslationColumn() {
    var transform = matrix_identity_float4x4
    transform.columns.3 = [1.5, 0.8, -2.25, 1]

    #expect(TransformReading.position(of: transform) == SIMD3<Float>(1.5, 0.8, -2.25))
}

@Test func yawOfAnIdentityTransformIsZero() {
    #expect(TransformReading.yaw(of: matrix_identity_float4x4) == 0)
}

@Test func yawMatchesTheRotationItWasBuiltFrom() {
    let angles: [Float] = [Float.pi / 6, .pi / 2, -.pi / 3, 2.5]
    for angle in angles {
        let rotation = simd_float4x4(simd_quatf(angle: angle, axis: [0, 1, 0]))
        #expect(abs(TransformReading.yaw(of: rotation) - angle) < 0.001)
    }
}

@Test func yawIgnoresTranslationAndScale() {
    let angle: Float = .pi / 4
    var transform = simd_float4x4(simd_quatf(angle: angle, axis: [0, 1, 0]))
    transform.columns.0 *= 3
    transform.columns.2 *= 3
    transform.columns.3 = [10, -4, 7, 1]

    #expect(abs(TransformReading.yaw(of: transform) - angle) < 0.001)
}
