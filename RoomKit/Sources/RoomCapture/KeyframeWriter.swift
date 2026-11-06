#if os(iOS)
import ARKit
import CoreImage
import Foundation
import RoomDressing

/// An ARKit pixel buffer handed to a background queue. ARKit never mutates a
/// delivered frame's buffers, so reading them elsewhere is safe.
struct PixelBufferBox: @unchecked Sendable {
    let buffer: CVPixelBuffer
}

/// Writes one dressing photo: JPEG, half-precision depth, manifest record.
/// Runs on a background queue.
struct KeyframeWriter: @unchecked Sendable {
    static let jpegQuality: Float = 0.75
    static let sharpnessSize = (width: 320, height: 240)

    let workspace: DressingWorkspace
    private let context = CIContext(options: [.cacheIntermediates: false])

    init(workspace: DressingWorkspace) {
        self.workspace = workspace
    }

    func write(
        image: PixelBufferBox, depth: PixelBufferBox, confidence: PixelBufferBox?,
        pose: CameraPose, timestamp: Double, index: Int
    ) throws -> (record: KeyframeRecord, depth: DepthMap) {
        let names = KeyframeRecord.fileNames(index: index)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let jpeg = context.jpegRepresentation(
                of: CIImage(cvPixelBuffer: image.buffer), colorSpace: space,
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption:
                            Self.jpegQuality])
        else { throw CocoaError(.fileWriteUnknown) }
        try jpeg.write(to: workspace.url(for: names.photo))

        let map = Self.depthMap(depth.buffer, confidence: confidence?.buffer)
        try DepthMapFile.encode(map).write(to: workspace.url(for: names.depth))

        let record = KeyframeRecord(
            file: names.photo, depthFile: names.depth, pose: pose, timestamp: timestamp,
            sharpness: Self.sharpness(of: image.buffer))
        return (record, map)
    }

    /// Float32 depth, with pixels of less than medium confidence set to 0.
    static func depthMap(_ depth: CVPixelBuffer, confidence: CVPixelBuffer?) -> DepthMap {
        CVPixelBufferLockBaseAddress(depth, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }
        if let confidence { CVPixelBufferLockBaseAddress(confidence, .readOnly) }
        defer { if let confidence { CVPixelBufferUnlockBaseAddress(confidence, .readOnly) } }

        let width = CVPixelBufferGetWidth(depth), height = CVPixelBufferGetHeight(depth)
        guard let base = CVPixelBufferGetBaseAddress(depth) else {
            return DepthMap(width: 0, height: 0, values: [])
        }
        let rowBytes = CVPixelBufferGetBytesPerRow(depth)
        let confidenceBase = confidence.flatMap { CVPixelBufferGetBaseAddress($0) }
        let confidenceRow = confidence.map { CVPixelBufferGetBytesPerRow($0) } ?? 0

        var values = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float32.self)
            for x in 0..<width {
                var value = row[x]
                if let confidenceBase {
                    let level = confidenceBase.advanced(by: y * confidenceRow + x)
                        .assumingMemoryBound(to: UInt8.self).pointee
                    if level < UInt8(ARConfidenceLevel.medium.rawValue) { value = 0 }
                }
                values[y * width + x] = value.isFinite ? value : 0
            }
        }
        return DepthMap(width: width, height: height, values: values)
    }

    /// Laplacian variance of the luma plane, subsampled to about 320×240.
    static func sharpness(of image: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(image, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(image, .readOnly) }
        guard CVPixelBufferGetPlaneCount(image) > 0,
              let base = CVPixelBufferGetBaseAddressOfPlane(image, 0) else { return 0 }
        let width = CVPixelBufferGetWidthOfPlane(image, 0)
        let height = CVPixelBufferGetHeightOfPlane(image, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(image, 0)
        let step = max(width / sharpnessSize.width, 1)
        let w = width / step, h = height / step
        var luma = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            let row = base.advanced(by: y * step * rowBytes).assumingMemoryBound(to: UInt8.self)
            for x in 0..<w { luma[y * w + x] = row[x * step] }
        }
        return Sharpness.varianceOfLaplacian(luma: luma, width: w, height: h)
    }
}

extension CameraPose {
    init(_ camera: ARCamera) {
        self.init(
            transform: camera.transform, intrinsics: camera.intrinsics,
            resolution: SIMD2(Int(camera.imageResolution.width), Int(camera.imageResolution.height)))
    }
}

extension MeshPiece {
    /// Copies an ARKit mesh anchor out of its Metal buffers.
    init(_ anchor: ARMeshAnchor) {
        let geometry = anchor.geometry
        func float3s(_ source: ARGeometrySource) -> [SIMD3<Float>] {
            let pointer = source.buffer.contents().advanced(by: source.offset)
            return (0..<source.count).map { i in
                let v = pointer.advanced(by: i * source.stride)
                    .assumingMemoryBound(to: (Float, Float, Float).self).pointee
                return SIMD3(v.0, v.1, v.2)
            }
        }
        let faces = geometry.faces
        let indexPointer = faces.buffer.contents()
        var indices = [UInt32]()
        indices.reserveCapacity(faces.count * 3)
        for i in 0..<(faces.count * faces.indexCountPerPrimitive) {
            indices.append(faces.bytesPerIndex == 4
                ? indexPointer.load(fromByteOffset: i * 4, as: UInt32.self)
                : UInt32(indexPointer.load(fromByteOffset: i * 2, as: UInt16.self)))
        }
        var classes = [UInt8](repeating: 0, count: faces.count)
        if let classification = geometry.classification {
            let pointer = classification.buffer.contents().advanced(by: classification.offset)
            for f in 0..<min(classification.count, faces.count) {
                classes[f] = pointer.advanced(by: f * classification.stride)
                    .assumingMemoryBound(to: UInt8.self).pointee
            }
        }
        self.init(
            localPositions: float3s(geometry.vertices), localNormals: float3s(geometry.normals),
            indices: indices, faceClasses: classes, transform: anchor.transform)
    }
}
#endif
