import Foundation

public enum Sharpness {
    /// Variance of the 4-neighbour Laplacian over the image interior: high for
    /// crisp edges, low for blur or flat areas.
    public static func varianceOfLaplacian(luma: [UInt8], width: Int, height: Int) -> Float {
        guard width > 2, height > 2, luma.count >= width * height else { return 0 }
        var sum: Double = 0
        var sumSquares: Double = 0
        var count = 0
        for y in 1..<(height - 1) {
            let row = y * width
            for x in 1..<(width - 1) {
                let i = row + x
                let response = Int(luma[i - 1]) + Int(luma[i + 1]) + Int(luma[i - width])
                    + Int(luma[i + width]) - 4 * Int(luma[i])
                let r = Double(response)
                sum += r
                sumSquares += r * r
                count += 1
            }
        }
        let mean = sum / Double(count)
        return Float(sumSquares / Double(count) - mean * mean)
    }
}
