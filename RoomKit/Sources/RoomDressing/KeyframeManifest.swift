import Foundation

/// One dressing photo, as listed in `photos.json`.
public struct KeyframeRecord: Codable, Equatable, Sendable {
    /// Relative to the room folder, e.g. `photos/007.jpg`.
    public var file: String
    /// Relative to the dressing workspace, e.g. `depth/007.f16`. Depth is only
    /// kept until the colours are computed.
    public var depthFile: String
    public var pose: CameraPose
    public var timestamp: Double
    public var sharpness: Float
    /// Photos are stored as the sensor gives them; the pose and intrinsics
    /// apply to this orientation.
    public var orientation: String

    public init(
        file: String, depthFile: String, pose: CameraPose, timestamp: Double,
        sharpness: Float, orientation: String = "landscapeRight"
    ) {
        self.file = file
        self.depthFile = depthFile
        self.pose = pose
        self.timestamp = timestamp
        self.sharpness = sharpness
        self.orientation = orientation
    }

    public static func fileNames(index: Int) -> (photo: String, depth: String) {
        let stem = String(format: "%03d", index)
        return ("photos/\(stem).jpg", "depth/\(stem).f16")
    }
}

public struct KeyframeManifest: Codable, Equatable, Sendable {
    public static let fileName = "photos.json"
    public var schemaVersion = 1
    public var keyframes: [KeyframeRecord]

    public init(keyframes: [KeyframeRecord] = []) {
        self.keyframes = keyframes
    }
}
