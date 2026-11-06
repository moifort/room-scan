import Foundation
import simd

public enum DressedMeshFileError: Error, Equatable {
    case badMagic
    case unsupportedVersion(UInt32)
    case truncated
}

/// Binary file for `DressedMesh`, little-endian:
/// `"RSDM"`, version, vertex count, triangle count, then positions and normals
/// (3 × Float32), colours (4 × UInt8), indices (3 × UInt32 per triangle) and
/// classes (UInt8 per triangle).
public enum DressedMeshFile {
    public static let fileName = "realistic.mesh"
    static let magic = Array("RSDM".utf8)
    static let version: UInt32 = 1

    public static func encode(_ mesh: DressedMesh) -> Data {
        var data = Data()
        data.reserveCapacity(16 + mesh.vertexCount * 28 + mesh.triangleCount * 13)
        data.append(contentsOf: magic)
        append(version, to: &data)
        append(UInt32(mesh.vertexCount), to: &data)
        append(UInt32(mesh.triangleCount), to: &data)
        for p in mesh.positions { append(p, to: &data) }
        for n in mesh.normals { append(n, to: &data) }
        for c in mesh.colors { data.append(contentsOf: [c.x, c.y, c.z, c.w]) }
        for i in mesh.indices { append(i, to: &data) }
        data.append(contentsOf: mesh.faceClasses)
        return data
    }

    public static func decode(_ data: Data) throws -> DressedMesh {
        var reader = Reader(bytes: [UInt8](data))
        guard reader.bytes.count >= 16 else {
            throw reader.bytes.count >= 4 && Array(reader.bytes[0..<4]) != magic
                ? DressedMeshFileError.badMagic : DressedMeshFileError.truncated
        }
        guard Array(reader.bytes[0..<4]) == magic else { throw DressedMeshFileError.badMagic }
        reader.offset = 4
        let fileVersion = try reader.uint32()
        guard fileVersion == version else { throw DressedMeshFileError.unsupportedVersion(fileVersion) }
        let vertices = Int(try reader.uint32())
        let triangles = Int(try reader.uint32())
        let expected = 16 + vertices * 28 + triangles * 13
        guard reader.bytes.count == expected else { throw DressedMeshFileError.truncated }

        var positions = [SIMD3<Float>](), normals = [SIMD3<Float>](), colors = [SIMD4<UInt8>]()
        positions.reserveCapacity(vertices)
        normals.reserveCapacity(vertices)
        colors.reserveCapacity(vertices)
        for _ in 0..<vertices { positions.append(try reader.float3()) }
        for _ in 0..<vertices { normals.append(try reader.float3()) }
        for _ in 0..<vertices {
            let b = try reader.take(4)
            colors.append(SIMD4(b[0], b[1], b[2], b[3]))
        }
        var indices = [UInt32]()
        indices.reserveCapacity(triangles * 3)
        for _ in 0..<(triangles * 3) { indices.append(try reader.uint32()) }
        let classes = try reader.take(triangles)
        guard indices.allSatisfy({ Int($0) < vertices }) else { throw DressedMeshFileError.truncated }
        return DressedMesh(
            positions: positions, normals: normals, colors: colors,
            indices: indices, faceClasses: classes)
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    private static func append(_ value: SIMD3<Float>, to data: inout Data) {
        for component in [value.x, value.y, value.z] {
            append(component.bitPattern, to: &data)
        }
    }

    private struct Reader {
        let bytes: [UInt8]
        var offset = 0

        mutating func take(_ count: Int) throws -> [UInt8] {
            guard offset + count <= bytes.count else { throw DressedMeshFileError.truncated }
            defer { offset += count }
            return Array(bytes[offset..<(offset + count)])
        }

        mutating func uint32() throws -> UInt32 {
            let b = try take(4)
            return UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
        }

        mutating func float3() throws -> SIMD3<Float> {
            SIMD3(Float(bitPattern: try uint32()), Float(bitPattern: try uint32()),
                  Float(bitPattern: try uint32()))
        }
    }
}
