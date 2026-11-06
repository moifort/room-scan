import Foundation
import simd

/// Where a photo was taken from, and how its pixels map to the world.
///
/// ARKit conventions: `transform` goes camera → world, the camera looks down
/// −Z with +Y up; pixels are those of the sensor image (landscape, origin top
/// left).
public struct CameraPose: Equatable, Sendable {
    public var transform: simd_float4x4
    public var intrinsics: simd_float3x3
    public var resolution: SIMD2<Int>

    public init(transform: simd_float4x4, intrinsics: simd_float3x3, resolution: SIMD2<Int>) {
        self.transform = transform
        self.intrinsics = intrinsics
        self.resolution = resolution
    }

    public var position: SIMD3<Float> {
        SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
    }

    /// Unit viewing direction (the camera's −Z axis) in world space.
    public var forward: SIMD3<Float> {
        -simd_normalize(SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z))
    }

    /// Pixel and depth (metres along the view axis) of a world point, or nil
    /// when the point is behind the camera.
    public func project(_ world: SIMD3<Float>) -> (pixel: SIMD2<Float>, depth: Float)? {
        let camera = transform.inverse * SIMD4(world, 1)
        let depth = -camera.z
        guard depth > 1e-4 else { return nil }
        let fx = intrinsics.columns.0.x, fy = intrinsics.columns.1.y
        let cx = intrinsics.columns.2.x, cy = intrinsics.columns.2.y
        return (SIMD2(fx * camera.x / depth + cx, -fy * camera.y / depth + cy), depth)
    }

    public func contains(pixel: SIMD2<Float>, margin: Float = 0) -> Bool {
        pixel.x >= margin && pixel.y >= margin
            && pixel.x <= Float(resolution.x) - 1 - margin
            && pixel.y <= Float(resolution.y) - 1 - margin
    }

    /// The same pose for an image resized by `factor`.
    public func scaled(by factor: Float) -> CameraPose {
        var k = intrinsics
        k.columns.0.x *= factor
        k.columns.1.y *= factor
        k.columns.2.x *= factor
        k.columns.2.y *= factor
        return CameraPose(
            transform: transform, intrinsics: k,
            resolution: SIMD2(Int((Float(resolution.x) * factor).rounded()),
                              Int((Float(resolution.y) * factor).rounded())))
    }
}

extension CameraPose: Codable {
    private enum CodingKeys: String, CodingKey { case transform, intrinsics, resolution }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let t = try c.decode([Float].self, forKey: .transform)
        let k = try c.decode([Float].self, forKey: .intrinsics)
        let r = try c.decode([Int].self, forKey: .resolution)
        guard t.count == 16, k.count == 9, r.count == 2 else {
            throw DecodingError.dataCorruptedError(
                forKey: .transform, in: c, debugDescription: "Unexpected matrix size")
        }
        transform = simd_float4x4(
            SIMD4(t[0], t[1], t[2], t[3]), SIMD4(t[4], t[5], t[6], t[7]),
            SIMD4(t[8], t[9], t[10], t[11]), SIMD4(t[12], t[13], t[14], t[15]))
        intrinsics = simd_float3x3(
            SIMD3(k[0], k[1], k[2]), SIMD3(k[3], k[4], k[5]), SIMD3(k[6], k[7], k[8]))
        resolution = SIMD2(r[0], r[1])
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let t = transform
        try c.encode([t.columns.0, t.columns.1, t.columns.2, t.columns.3]
            .flatMap { [$0.x, $0.y, $0.z, $0.w] }, forKey: .transform)
        let k = intrinsics
        try c.encode([k.columns.0, k.columns.1, k.columns.2]
            .flatMap { [$0.x, $0.y, $0.z] }, forKey: .intrinsics)
        try c.encode([resolution.x, resolution.y], forKey: .resolution)
    }
}
