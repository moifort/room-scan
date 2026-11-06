import Foundation
import Testing
@testable import RoomDressing

extension DressedMesh {
    /// One seat-classified triangle with distinct colours.
    static let sampleTriangle = DressedMesh(
        positions: [[0, 0, 0], [1, 0, 0], [0, 1, 0.5]],
        normals: [[0, 0, 1], [0, 0, 1], [0, 0.2, 0.98]],
        colors: [[255, 0, 0, 255], [0, 255, 0, 255], DressedMesh.unseenColor],
        indices: [0, 1, 2],
        faceClasses: [MeshClass.seat.rawValue])
}

@Test func encodedMeshDecodesIdentically() throws {
    let mesh = DressedMesh.sampleTriangle
    #expect(try DressedMeshFile.decode(DressedMeshFile.encode(mesh)) == mesh)
}

@Test func wrongMagicThrows() {
    #expect(throws: DressedMeshFileError.badMagic) {
        try DressedMeshFile.decode(Data("XXXX".utf8) + Data(count: 32))
    }
}

@Test func truncatedFileThrows() {
    let data = DressedMeshFile.encode(.sampleTriangle)
    #expect(throws: DressedMeshFileError.truncated) {
        try DressedMeshFile.decode(data.prefix(data.count - 5))
    }
}

@Test func unknownVersionThrows() {
    var bytes = [UInt8](DressedMeshFile.encode(.sampleTriangle))
    bytes[4] = 9
    #expect(throws: DressedMeshFileError.unsupportedVersion(9)) {
        try DressedMeshFile.decode(Data(bytes))
    }
}

@Test func emptyMeshRoundTrips() throws {
    #expect(try DressedMeshFile.decode(DressedMeshFile.encode(.empty)) == .empty)
}
