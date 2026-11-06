import Foundation
import simd

/// An 8-bit RGB image, row by row.
public struct RGBImage: Sendable {
    public var width: Int
    public var height: Int
    public var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public static func solid(width: Int, height: Int, color: SIMD3<UInt8>) -> RGBImage {
        RGBImage(width: width, height: height,
                 pixels: (0..<(width * height)).flatMap { _ in [color.x, color.y, color.z] })
    }

    /// Bilinear sample, 0…255 per channel, or nil outside the image.
    public func bilinear(at p: SIMD2<Float>) -> SIMD3<Float>? {
        guard p.x >= 0, p.y >= 0, p.x <= Float(width - 1), p.y <= Float(height - 1) else { return nil }
        let x0 = Int(p.x), y0 = Int(p.y)
        let x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
        let fx = p.x - Float(x0), fy = p.y - Float(y0)
        func at(_ x: Int, _ y: Int) -> SIMD3<Float> {
            let i = (y * width + x) * 3
            return SIMD3(Float(pixels[i]), Float(pixels[i + 1]), Float(pixels[i + 2]))
        }
        let top = at(x0, y0) * (1 - fx) + at(x1, y0) * fx
        let bottom = at(x0, y1) * (1 - fx) + at(x1, y1) * fx
        return top * (1 - fy) + bottom * fy
    }
}

public enum VertexColorizer {
    static let samplesPerVertex = 3
    static let neighbourPasses = 3

    /// Colours every vertex from the photos that see it best.
    ///
    /// The outer loop runs over photos so that only one image is in memory at
    /// a time; each vertex keeps its three best-weighted samples. `loadImage`
    /// may return an image smaller than the pose resolution (e.g. half size):
    /// sampling is scaled to it.
    public static func colourize(
        _ mesh: inout DressedMesh, views: [ColorView],
        loadImage: (Int) throws -> RGBImage, progress: (Double) -> Void
    ) throws {
        let count = mesh.vertexCount
        let k = samplesPerVertex
        var weights = [Float](repeating: 0, count: count * k)
        var samples = [SIMD3<Float>](repeating: .zero, count: count * k)
        let maxSharpness = views.map(\.sharpness).max() ?? 0

        for (index, view) in views.enumerated() {
            let image = try loadImage(index)
            let scale = SIMD2(Float(image.width) / Float(view.pose.resolution.x),
                              Float(image.height) / Float(view.pose.resolution.y))
            let sharpnessFactor = maxSharpness > 0 ? max(view.sharpness / maxSharpness, 0.05) : 1

            for v in 0..<count {
                guard let hit = Visibility.hit(point: mesh.positions[v], normal: mesh.normals[v], in: view),
                      let color = image.bilinear(at: hit.pixel * scale)
                else { continue }
                let weight = hit.weight * sharpnessFactor
                // Replace the weakest of the three kept samples if this one is better.
                var weakest = v * k
                for slot in (v * k)..<(v * k + k) where weights[slot] < weights[weakest] {
                    weakest = slot
                }
                if weight > weights[weakest] {
                    weights[weakest] = weight
                    samples[weakest] = color
                }
            }
            progress(Double(index + 1) / Double(views.count))
        }
        if views.isEmpty { progress(1) }

        var seen = [Bool](repeating: false, count: count)
        for v in 0..<count {
            var total: Float = 0
            var sum = SIMD3<Float>.zero
            for slot in (v * k)..<(v * k + k) where weights[slot] > 0 {
                total += weights[slot]
                sum += samples[slot] * weights[slot]
            }
            if total > 0 {
                let c = simd_clamp(sum / total, SIMD3(repeating: 0), SIMD3(repeating: 255))
                mesh.colors[v] = SIMD4(UInt8(c.x.rounded()), UInt8(c.y.rounded()),
                                       UInt8(c.z.rounded()), 255)
                seen[v] = true
            } else {
                mesh.colors[v] = DressedMesh.unseenColor
            }
        }
        fillUnseen(&mesh, seen: seen)
    }

    /// Unseen vertices take the mean colour of their coloured neighbours, a
    /// few rings deep; their alpha stays 0 since no photo saw them.
    static func fillUnseen(_ mesh: inout DressedMesh, seen: [Bool]) {
        guard seen.contains(false), seen.contains(true) else { return }
        var neighbours = [[Int]](repeating: [], count: mesh.vertexCount)
        for t in 0..<mesh.triangleCount {
            let (a, b, c) = mesh.triangle(t)
            neighbours[a] += [b, c]
            neighbours[b] += [a, c]
            neighbours[c] += [a, b]
        }
        var known = seen
        for _ in 0..<neighbourPasses {
            var updates: [(Int, SIMD4<UInt8>)] = []
            for v in 0..<mesh.vertexCount where !known[v] {
                let donors = neighbours[v].filter { known[$0] }
                guard !donors.isEmpty else { continue }
                var sum = SIMD3<Float>.zero
                for d in donors {
                    let c = mesh.colors[d]
                    sum += SIMD3(Float(c.x), Float(c.y), Float(c.z))
                }
                let mean = sum / Float(donors.count)
                updates.append((v, SIMD4(UInt8(mean.x.rounded()), UInt8(mean.y.rounded()),
                                         UInt8(mean.z.rounded()), 0)))
            }
            guard !updates.isEmpty else { break }
            for (v, color) in updates {
                mesh.colors[v] = color
                known[v] = true
            }
        }
    }
}
