import CoreGraphics
import Foundation
import ImageIO
import RoomModel
import UniformTypeIdentifiers
import simd

public enum ThumbnailRendererError: Error, Equatable {
    case contextUnavailable
    case encodingFailed
}

/// Dessine le plan de la pièce vu du dessus : contour des murs et empreintes
/// des meubles. Un dessin 2D plutôt qu'une capture de la scène 3D — c'est
/// déterministe, testable sans écran, et sans dépendance au moteur de rendu.
public enum ThumbnailRenderer {
    public static func pngData(for room: ScannedRoom, pixelSize: Int = 400) throws -> Data {
        let size = max(pixelSize, 32)
        guard let context = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw ThumbnailRendererError.contextUnavailable }

        context.setFillColor(CGColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))

        let transform = makeTransform(for: room, pixelSize: CGFloat(size))
        drawFloor(room.floor, in: context, transform: transform)
        drawWalls(room.walls, in: context, transform: transform)
        drawFurniture(room.furniture, in: context, transform: transform)

        guard let image = context.makeImage() else {
            throw ThumbnailRendererError.contextUnavailable
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil)
        else { throw ThumbnailRendererError.encodingFailed }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ThumbnailRendererError.encodingFailed
        }
        return output as Data
    }

    /// Convertit les mètres de la pièce en pixels, centrés dans la vignette.
    private static func makeTransform(
        for room: ScannedRoom, pixelSize: CGFloat
    ) -> (SIMD2<Float>) -> CGPoint {
        let extent = max(room.floor.size.x, room.floor.size.y, 1)
        let scale = pixelSize * 0.82 / CGFloat(extent)
        let center = room.floor.center

        return { point in
            let offset = point - center
            return CGPoint(
                x: pixelSize / 2 + CGFloat(offset.x) * scale,
                y: pixelSize / 2 - CGFloat(offset.y) * scale)
        }
    }

    private static func drawFloor(
        _ floor: FloorOutline, in context: CGContext,
        transform: (SIMD2<Float>) -> CGPoint
    ) {
        guard floor.points.count > 2 else { return }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.beginPath()
        context.move(to: transform(floor.points[0]))
        for point in floor.points.dropFirst() {
            context.addLine(to: transform(point))
        }
        context.closePath()
        context.fillPath()
    }

    private static func drawWalls(
        _ walls: [Wall], in context: CGContext,
        transform: (SIMD2<Float>) -> CGPoint
    ) {
        context.setStrokeColor(CGColor(red: 0.24, green: 0.26, blue: 0.30, alpha: 1))
        context.setLineWidth(3)
        context.setLineCap(.round)

        for wall in walls {
            let direction = SIMD2(cos(wall.yaw), -sin(wall.yaw)) * (wall.width / 2)
            context.move(to: transform(wall.groundPosition - direction))
            context.addLine(to: transform(wall.groundPosition + direction))
        }
        context.strokePath()
    }

    private static func drawFurniture(
        _ furniture: [FurniturePiece], in context: CGContext,
        transform: (SIMD2<Float>) -> CGPoint
    ) {
        context.setFillColor(CGColor(red: 0.35, green: 0.55, blue: 0.78, alpha: 0.75))

        for piece in furniture {
            let halfWidth = piece.footprint.x / 2
            let halfDepth = piece.footprint.y / 2
            let corners: [SIMD2<Float>] = [
                [-halfWidth, -halfDepth], [halfWidth, -halfDepth],
                [halfWidth, halfDepth], [-halfWidth, halfDepth],
            ]
            let rotated = corners.map { corner -> SIMD2<Float> in
                let x = corner.x * cos(piece.yaw) - corner.y * sin(piece.yaw)
                let y = corner.x * sin(piece.yaw) + corner.y * cos(piece.yaw)
                return piece.groundPosition + SIMD2(x, y)
            }

            context.beginPath()
            context.move(to: transform(rotated[0]))
            for corner in rotated.dropFirst() {
                context.addLine(to: transform(corner))
            }
            context.closePath()
            context.fillPath()
        }
    }
}
