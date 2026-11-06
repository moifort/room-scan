import Foundation
import RoomModel
import simd

/// A visitor standing in the room at eye height: looks around, and walks to
/// a point of the floor. Purely geometric, like `OrbitCamera`.
public struct FirstPersonCamera: Equatable, Sendable {
    public static let eyeHeight: Float = 1.6
    /// Just under straight up or down, so the view never flips.
    public static let maxPitch: Float = 1.4

    public private(set) var position: SIMD3<Float>
    /// 0 looks towards −Z; positive turns left.
    public private(set) var yaw: Float
    public private(set) var pitch: Float = 0

    public init(floorPoint: SIMD2<Float>, floorHeight: Float, yaw: Float = 0) {
        position = SIMD3(floorPoint.x, floorHeight + Self.eyeHeight, floorPoint.y)
        self.yaw = yaw
    }

    public var floorHeight: Float { position.y - Self.eyeHeight }

    public var forward: SIMD3<Float> {
        SIMD3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
    }

    var right: SIMD3<Float> { SIMD3(cos(yaw), 0, -sin(yaw)) }

    public mutating func look(deltaYaw: Float, deltaPitch: Float) {
        yaw += deltaYaw
        pitch = min(max(pitch + deltaPitch, -Self.maxPitch), Self.maxPitch)
    }

    /// Walks to a floor point, stopping at the edge of the room if the point
    /// lies outside it.
    public mutating func walk(to floorPoint: SIMD2<Float>, within outline: FloorOutline) {
        let start = SIMD2(position.x, position.z)
        var destination = floorPoint
        if outline.points.count > 2, !outline.contains(floorPoint) {
            // Last point of the segment still inside the room.
            var inside: Float = 0, outside: Float = 1
            for _ in 0..<16 {
                let mid = (inside + outside) / 2
                if outline.contains(start + (floorPoint - start) * mid) { inside = mid } else { outside = mid }
            }
            destination = start + (floorPoint - start) * inside
        }
        position.x = destination.x
        position.z = destination.y
    }

    /// Floor point under a screen point, or nil when the ray misses the floor
    /// (above the horizon). `normalizedScreenPoint` runs from −1 to 1, with +y up.
    public func floorHit(
        normalizedScreenPoint p: SIMD2<Float>, verticalFieldOfView: Float, aspectRatio: Float
    ) -> SIMD2<Float>? {
        let tanV = tan(verticalFieldOfView / 2)
        let up = simd_cross(right, forward)
        let direction = simd_normalize(forward + right * (p.x * tanV * aspectRatio) + up * (p.y * tanV))
        guard direction.y < -1e-4 else { return nil }
        let t = (floorHeight - position.y) / direction.y
        let hit = position + direction * t
        return SIMD2(hit.x, hit.z)
    }
}
