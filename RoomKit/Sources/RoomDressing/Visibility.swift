import Foundation
import simd

/// A dressing photo as the colouring and coverage passes see it.
public struct ColorView: Sendable {
    public var pose: CameraPose
    public var depth: DepthMap
    public var sharpness: Float

    public init(pose: CameraPose, depth: DepthMap, sharpness: Float) {
        self.pose = pose
        self.depth = depth
        self.sharpness = sharpness
    }
}

public enum Visibility {
    public static let maxDistance: Float = 3.0
    /// cos 60°: beyond that angle a surface is seen too obliquely.
    public static let minCosine: Float = 0.5
    public static let depthTolerance: Float = 0.05
    static let frameMargin: Float = 2

    public struct Hit: Sendable {
        public var pixel: SIMD2<Float>
        public var weight: Float
    }

    /// How well a photo sees a surface point, or nil when it does not see it:
    /// out of frame, behind, too far, too oblique, or hidden by something
    /// nearer according to the photo's own depth.
    public static func hit(point: SIMD3<Float>, normal: SIMD3<Float>, in view: ColorView) -> Hit? {
        guard let projection = view.pose.project(point),
              projection.depth <= maxDistance,
              view.pose.contains(pixel: projection.pixel, margin: frameMargin)
        else { return nil }

        let toCamera = view.pose.position - point
        let distance = simd_length(toCamera)
        guard distance > 0 else { return nil }
        let cosine = simd_dot(normal, toCamera / distance)
        guard cosine >= minCosine else { return nil }

        if let measured = view.depth.depth(atPixel: projection.pixel,
                                           imageResolution: view.pose.resolution),
           abs(measured - projection.depth) > depthTolerance {
            return nil
        }
        let d = max(projection.depth, 0.3)
        return Hit(pixel: projection.pixel, weight: cosine * cosine / (d * d))
    }

    public static func weight(of point: SIMD3<Float>, normal: SIMD3<Float>, in view: ColorView) -> Float? {
        hit(point: point, normal: normal, in: view)?.weight
    }
}
