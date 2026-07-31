import Foundation
import ImageIO
import Testing
import RoomModel
@testable import RoomStore

@Test func thumbnailIsAValidPNGOfTheRequestedSize() throws {
    let data = try ThumbnailRenderer.pngData(for: .demoLivingRoom, pixelSize: 240)

    #expect(data.count > 200)
    // Signature PNG.
    #expect(Array(data.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])

    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(image.width == 240)
    #expect(image.height == 240)
}

@Test func thumbnailOfARoomWithFurnitureDiffersFromAnEmptyOne() throws {
    let room = ScannedRoom.demoLivingRoom
    let emptied = ScannedRoom(
        walls: room.walls, openings: room.openings, furniture: [], floor: room.floor)

    let withFurniture = try ThumbnailRenderer.pngData(for: room, pixelSize: 240)
    let withoutFurniture = try ThumbnailRenderer.pngData(for: emptied, pixelSize: 240)

    #expect(withFurniture != withoutFurniture)
}

@Test func roomWithoutGeometryStillProducesAThumbnail() throws {
    let empty = ScannedRoom(walls: [], openings: [], furniture: [], floor: FloorOutline(points: []))
    let data = try ThumbnailRenderer.pngData(for: empty, pixelSize: 120)
    #expect(data.count > 100)
}
