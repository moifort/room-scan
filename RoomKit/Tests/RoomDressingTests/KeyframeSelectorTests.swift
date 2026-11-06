import Foundation
import Testing
import simd
@testable import RoomDressing

private func pose(x: Float = 0, yaw: Float = 0) -> simd_float4x4 {
    var t = simd_float4x4(simd_quatf(angle: yaw, axis: [0, 1, 0]))
    t.columns.3 = SIMD4(x, 0, 0, 1)
    return t
}

@Test func stillCameraIsAcceptedOnceThenNotNovel() {
    var s = KeyframeSelector()
    #expect(s.evaluate(time: 0, transform: pose(), trackingNormal: true) == .insufficientHistory)
    #expect(s.evaluate(time: 0.1, transform: pose(), trackingNormal: true) == .accept)
    #expect(s.evaluate(time: 0.2, transform: pose(), trackingNormal: true) == .notNovel)
}

@Test func framesInsideTheIntervalAreSkipped() {
    var s = KeyframeSelector()
    _ = s.evaluate(time: 0, transform: pose(), trackingNormal: true)
    #expect(s.evaluate(time: 0.03, transform: pose(), trackingNormal: true) == .skippedInterval)
}

@Test func slowThirtyCentimetreMoveIsAcceptedAgain() {
    var s = KeyframeSelector()
    for step in 0...30 {
        _ = s.evaluate(time: Double(step) * 0.1, transform: pose(x: Float(step) * 0.01),
                       trackingNormal: true)
    }
    #expect(s.accepted.count == 2)
}

@Test func turningTwentyFiveDegreesInPlaceIsNovel() {
    var s = KeyframeSelector()
    var yaw: Float = 0
    for step in 0...20 {
        _ = s.evaluate(time: Double(step) * 0.1, transform: pose(yaw: yaw), trackingNormal: true)
        yaw += 0.022  // 0.22 rad/s, under the speed limit
    }
    #expect(s.accepted.count == 2)
}

@Test func ninetyDegreesPerSecondIsTooFast() {
    var s = KeyframeSelector()
    _ = s.evaluate(time: 0, transform: pose(), trackingNormal: true)
    #expect(s.evaluate(time: 0.1, transform: pose(yaw: 0.157), trackingNormal: true) == .tooFast)
}

@Test func walkingFastIsTooFast() {
    var s = KeyframeSelector()
    _ = s.evaluate(time: 0, transform: pose(), trackingNormal: true)
    #expect(s.evaluate(time: 0.1, transform: pose(x: 0.1), trackingNormal: true) == .tooFast)
}

@Test func limitedTrackingIsRejected() {
    var s = KeyframeSelector()
    _ = s.evaluate(time: 0, transform: pose(), trackingNormal: true)
    #expect(s.evaluate(time: 0.1, transform: pose(), trackingNormal: false) == .trackingLimited)
}

@Test func capStopsAcceptingAt200() {
    var s = KeyframeSelector(thresholds: .init(maxLinearSpeed: 100))
    var last: KeyframeSelector.Decision = .accept
    for step in 0...202 {
        last = s.evaluate(time: Double(step) * 0.1, transform: pose(x: Float(step) * 0.3),
                          trackingNormal: true)
    }
    #expect(s.accepted.count == 200)
    #expect(last == .capReached)
}

@Test func fastMotionRaisesWarning() {
    var s = KeyframeSelector()
    #expect(!s.isMovingTooFast)
    for step in 0...10 {
        _ = s.evaluate(time: Double(step) * 0.1, transform: pose(yaw: Float(step) * 0.3),
                       trackingNormal: true)
    }
    #expect(s.isMovingTooFast)
}
