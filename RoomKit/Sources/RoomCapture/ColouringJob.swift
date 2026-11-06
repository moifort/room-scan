#if os(iOS)
import CoreGraphics
import Foundation
import ImageIO
import RoomDressing

/// Colours the dressing mesh from its photos, off the main thread, and writes
/// `realistic.mesh` into the workspace. Depth maps are deleted afterwards:
/// they only serve this pass.
enum ColouringJob {
    /// Photos are read at half size: plenty for per-vertex colour, and four
    /// times less memory per image.
    static let imageScale: CGFloat = 0.5

    static func run(
        mesh: DressedMesh, workspace: DressingWorkspace,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            var mesh = mesh
            let manifest = try workspace.readManifest()
            let views = try manifest.keyframes.map { record in
                ColorView(
                    pose: record.pose,
                    depth: try DepthMapFile.decode(Data(contentsOf: workspace.url(for: record.depthFile))),
                    sharpness: record.sharpness)
            }
            try VertexColorizer.colourize(
                &mesh, views: views,
                loadImage: { index in
                    try Task.checkCancellation()
                    let record = manifest.keyframes[index]
                    let width = CGFloat(record.pose.resolution.x) * imageScale
                    return try loadRGB(workspace.url(for: record.file), maxPixelSize: Int(width))
                },
                progress: progress)
            try Task.checkCancellation()
            try DressedMeshFile.encode(mesh).write(to: workspace.meshURL, options: .atomic)
            try? FileManager.default.removeItem(at: workspace.depthDirectory)
        }.value
    }

    /// Decodes a JPEG, downscaled, into packed 8-bit RGB.
    static func loadRGB(_ url: URL, maxPixelSize: Int) throws -> RGBImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceCreateThumbnailWithTransform: false,
              ] as CFDictionary)
        else { throw CocoaError(.fileReadCorruptFile) }

        let width = image.width, height = image.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &rgba, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw CocoaError(.fileReadCorruptFile) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var rgb = [UInt8](repeating: 0, count: width * height * 3)
        for i in 0..<(width * height) {
            rgb[3 * i] = rgba[4 * i]
            rgb[3 * i + 1] = rgba[4 * i + 1]
            rgb[3 * i + 2] = rgba[4 * i + 2]
        }
        return RGBImage(width: width, height: height, pixels: rgb)
    }
}
#endif
