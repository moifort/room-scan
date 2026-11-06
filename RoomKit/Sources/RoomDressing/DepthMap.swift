import Foundation
import simd

/// LiDAR depth captured with a photo, in metres. Zero marks a pixel with no
/// trustworthy measurement.
public struct DepthMap: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var values: [Float]

    public init(width: Int, height: Int, values: [Float]) {
        self.width = width
        self.height = height
        self.values = values
    }

    /// Depth under a pixel of the (larger) photo it was captured with.
    public func depth(atPixel p: SIMD2<Float>, imageResolution: SIMD2<Int>) -> Float? {
        guard width > 0, height > 0 else { return nil }
        let x = Int(p.x * Float(width) / Float(imageResolution.x))
        let y = Int(p.y * Float(height) / Float(imageResolution.y))
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let value = values[y * width + x]
        return value > 0 ? value : nil
    }
}

public enum DepthMapFileError: Error, Equatable { case truncated }

/// `UInt32` width, `UInt32` height, then half-precision values, row by row.
public enum DepthMapFile {
    public static func encode(_ map: DepthMap) -> Data {
        var data = Data(capacity: 8 + map.values.count * 2)
        for v in [UInt32(map.width), UInt32(map.height)] {
            withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) }
        }
        for value in map.values {
            withUnsafeBytes(of: Float16(value).bitPattern.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    public static func decode(_ data: Data) throws -> DepthMap {
        let bytes = [UInt8](data)
        guard bytes.count >= 8 else { throw DepthMapFileError.truncated }
        func u32(_ o: Int) -> Int {
            Int(UInt32(bytes[o]) | UInt32(bytes[o + 1]) << 8 | UInt32(bytes[o + 2]) << 16
                | UInt32(bytes[o + 3]) << 24)
        }
        let width = u32(0), height = u32(4)
        guard bytes.count == 8 + width * height * 2 else { throw DepthMapFileError.truncated }
        var values = [Float](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            let o = 8 + 2 * i
            values[i] = Float(Float16(bitPattern: UInt16(bytes[o]) | UInt16(bytes[o + 1]) << 8))
        }
        return DepthMap(width: width, height: height, values: values)
    }
}
