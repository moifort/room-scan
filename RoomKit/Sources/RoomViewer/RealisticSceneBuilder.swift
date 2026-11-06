#if os(iOS)
import Foundation
import RoomDressing
import SceneKit
import UIKit

/// Turns a dressed mesh into a SceneKit node coloured per vertex.
///
/// SceneKit rather than RealityKit: RealityKit's materials ignore vertex
/// colours unless a custom Metal shader reads them, and the Metal toolchain is
/// not part of this project's build. SceneKit reads a `.color` geometry source
/// natively.
@MainActor
public enum RealisticSceneBuilder {
    public static func node(for mesh: DressedMesh) -> SCNNode {
        guard !mesh.isEmpty else { return SCNNode() }

        let positions = mesh.positions.map { SCNVector3($0.x, $0.y, $0.z) }
        let normals = mesh.normals.map { SCNVector3($0.x, $0.y, $0.z) }
        // Unseen vertices stay neutral grey but opaque: alpha only tells the
        // colouring pass whether a photo saw them.
        // Float RGB: SceneKit ignores 8-bit colour sources on some renderers.
        // It also reads vertex colours as linear, while photo colours are
        // sRGB: convert, or every surface comes out washed out.
        var colorComponents = [Float]()
        colorComponents.reserveCapacity(mesh.vertexCount * 3)
        for c in mesh.colors {
            colorComponents += [linear(c.x), linear(c.y), linear(c.z)]
        }
        let colorData = colorComponents.withUnsafeBufferPointer { Data(buffer: $0) }
        let colorSource = SCNGeometrySource(
            data: colorData, semantic: .color, vectorCount: mesh.vertexCount,
            usesFloatComponents: true, componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0, dataStride: 3 * MemoryLayout<Float>.size)
        let indexData = mesh.indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(
            data: indexData, primitiveType: .triangles,
            primitiveCount: mesh.triangleCount, bytesPerIndex: 4)

        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: positions),
                      SCNGeometrySource(normals: normals), colorSource],
            elements: [element])
        let material = SCNMaterial()
        // The photos already contain the room's light: no shading on top.
        material.lightingModel = .constant
        material.diffuse.contents = UIColor.white
        // One-sided: ARKit faces look towards where the sensor stood, i.e.
        // into the room. Seen from outside, walls and ceiling vanish and the
        // room opens like a doll's house; from inside, everything shows.
        material.isDoubleSided = false
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }

    private static let linearTable: [Float] = (0...255).map { value in
        let c = Float(value) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func linear(_ value: UInt8) -> Float { linearTable[Int(value)] }
}
#endif
