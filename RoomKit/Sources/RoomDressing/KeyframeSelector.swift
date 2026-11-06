import Foundation
import simd

/// Decides which camera frames become dressing photos: sharp (the phone is
/// nearly still) and showing something new (far enough, or turned enough,
/// from every photo already kept).
public struct KeyframeSelector: Sendable {
    public struct Thresholds: Sendable {
        public var maxAngularSpeed: Float
        public var maxLinearSpeed: Float
        public var minTranslation: Float
        public var minRotation: Float
        public var cap: Int
        public var evaluationInterval: TimeInterval

        public init(
            maxAngularSpeed: Float = 0.5, maxLinearSpeed: Float = 0.3,
            minTranslation: Float = 0.25, minRotation: Float = 0.35,
            cap: Int = 200, evaluationInterval: TimeInterval = 0.1
        ) {
            self.maxAngularSpeed = maxAngularSpeed
            self.maxLinearSpeed = maxLinearSpeed
            self.minTranslation = minTranslation
            self.minRotation = minRotation
            self.cap = cap
            self.evaluationInterval = evaluationInterval
        }
    }

    public enum Decision: Equatable, Sendable {
        case accept, skippedInterval, insufficientHistory, trackingLimited, tooFast, notNovel, capReached
    }

    public let thresholds: Thresholds
    public private(set) var accepted: [simd_float4x4] = []
    private var history: [(time: TimeInterval, transform: simd_float4x4)] = []
    private var lastEvaluation: TimeInterval?
    private var recent: [Decision] = []

    /// Speed is measured against a sample at least this old.
    static let speedWindow: TimeInterval = 0.1
    static let epsilon: TimeInterval = 1e-6

    public init(thresholds: Thresholds = Thresholds()) {
        self.thresholds = thresholds
    }

    /// True when at least 5 of the last 10 evaluated frames were too fast.
    public var isMovingTooFast: Bool {
        recent.filter { $0 == .tooFast }.count >= 5
    }

    public mutating func evaluate(
        time: TimeInterval, transform: simd_float4x4, trackingNormal: Bool
    ) -> Decision {
        if let last = lastEvaluation, time - last < thresholds.evaluationInterval - Self.epsilon {
            return .skippedInterval
        }
        lastEvaluation = time
        let decision = decide(time: time, transform: transform, trackingNormal: trackingNormal)
        history.append((time, transform))
        history.removeAll { time - $0.time > 1 }
        recent.append(decision)
        if recent.count > 10 { recent.removeFirst(recent.count - 10) }
        if decision == .accept { accepted.append(transform) }
        return decision
    }

    private func decide(
        time: TimeInterval, transform: simd_float4x4, trackingNormal: Bool
    ) -> Decision {
        guard trackingNormal else { return .trackingLimited }
        guard let reference = history.last(where: {
            time - $0.time >= Self.speedWindow - Self.epsilon
        }) else { return .insufficientHistory }

        let dt = Float(time - reference.time)
        let linear = simd_distance(Self.position(transform), Self.position(reference.transform)) / dt
        let angular = Self.rotationAngle(from: reference.transform, to: transform) / dt
        guard linear <= thresholds.maxLinearSpeed, angular <= thresholds.maxAngularSpeed else {
            return .tooFast
        }
        guard accepted.count < thresholds.cap else { return .capReached }

        let position = Self.position(transform)
        let forward = Self.forward(transform)
        let isNovel = accepted.allSatisfy { kept in
            simd_distance(position, Self.position(kept)) > thresholds.minTranslation
                || Self.angle(between: forward, and: Self.forward(kept)) > thresholds.minRotation
        }
        return isNovel ? .accept : .notNovel
    }

    static func position(_ t: simd_float4x4) -> SIMD3<Float> {
        SIMD3(t.columns.3.x, t.columns.3.y, t.columns.3.z)
    }

    static func forward(_ t: simd_float4x4) -> SIMD3<Float> {
        -simd_normalize(SIMD3(t.columns.2.x, t.columns.2.y, t.columns.2.z))
    }

    static func angle(between a: SIMD3<Float>, and b: SIMD3<Float>) -> Float {
        acos(min(max(simd_dot(a, b), -1), 1))
    }

    /// Angle of the rotation taking one orientation to the other.
    static func rotationAngle(from a: simd_float4x4, to b: simd_float4x4) -> Float {
        func rotation(_ t: simd_float4x4) -> simd_float3x3 {
            simd_float3x3(SIMD3(t.columns.0.x, t.columns.0.y, t.columns.0.z),
                          SIMD3(t.columns.1.x, t.columns.1.y, t.columns.1.z),
                          SIMD3(t.columns.2.x, t.columns.2.y, t.columns.2.z))
        }
        let relative = rotation(a).transpose * rotation(b)
        let trace = relative.columns.0.x + relative.columns.1.y + relative.columns.2.z
        return acos(min(max((trace - 1) / 2, -1), 1))
    }
}
