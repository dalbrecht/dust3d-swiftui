import Dust3DEngine
import Foundation

struct MeshSourceCounts {
    let corners: Int
    let influences: Int
    let identities: Int
    let expandedVertices: Int
    let nodes: Int
    let payload: Int

    func validate(maximumPayloadBytes: Int) throws {
        guard expandedVertices > 0, expandedVertices.isMultiple(of: 3), corners == expandedVertices,
            influences >= 0, identities >= 0, nodes >= 0, identities == nodes,
            payload > 0, payload <= maximumPayloadBytes,
            corners <= payload / MemoryLayout<Dust3DSourceCorner>.stride
        else { throw MeshSourceDataError.invalidBufferCounts }
        let afterCorners = payload - corners * MemoryLayout<Dust3DSourceCorner>.stride
        guard influences <= afterCorners / MemoryLayout<Dust3DSourceInfluence>.stride else {
            throw MeshSourceDataError.invalidBufferCounts
        }
        let afterInfluences = afterCorners - influences * MemoryLayout<Dust3DSourceInfluence>.stride
        guard identities <= afterInfluences / 2 else { throw MeshSourceDataError.invalidBufferCounts }
    }
}

enum MeshSourceCopy {
    static func identifier(_ pointer: UnsafePointer<CChar>?) throws -> String {
        guard let pointer else { throw MeshSourceDataError.invalidIdentity }
        // Current native validation accepts only 36/38-byte UUID-shaped keys,
        // without requiring hex digits. Never read an unbounded C string.
        let maximumBytes = 38
        var bytes: [UInt8] = []
        while bytes.count < maximumBytes {
            let value = pointer[bytes.count]
            if value == 0 { return try decodeIdentifier(bytes) }
            bytes.append(UInt8(bitPattern: value))
        }
        guard pointer[maximumBytes] == 0 else { throw MeshSourceDataError.invalidIdentity }
        return try decodeIdentifier(bytes)
    }

    private static func decodeIdentifier(_ bytes: [UInt8]) throws -> String {
        guard !bytes.isEmpty, let value = String(bytes: bytes, encoding: .utf8) else {
            throw MeshSourceDataError.invalidIdentity
        }
        return value
    }

    static func copy(_ owner: OpaquePointer, geometry: OpaquePointer, maximumPayloadBytes: Int) throws
        -> MeshSourceHints
    {
        do {
            let counts = MeshSourceCounts(
                corners: dust3d_sourced_mesh_corner_count(owner),
                influences: dust3d_sourced_mesh_influence_count(owner),
                identities: dust3d_sourced_mesh_identity_count(owner),
                expandedVertices: dust3d_mesh_vertex_count(geometry), nodes: dust3d_mesh_node_count(geometry),
                payload: dust3d_sourced_mesh_payload_bytes(owner))
            try counts.validate(maximumPayloadBytes: maximumPayloadBytes)
            guard let corners = dust3d_sourced_mesh_corners(owner) else {
                throw MeshSourceDataError.invalidBufferCounts
            }
            let influences = dust3d_sourced_mesh_influences(owner)
            guard counts.influences == 0 || influences != nil else { throw MeshSourceDataError.invalidBufferCounts }
            let identities = try (0..<counts.identities).map { index in
                try Task.checkCancellation()
                return MeshSourceIdentity(
                    nodeID: try identifier(dust3d_sourced_mesh_node_id(owner, index)),
                    partID: try identifier(dust3d_sourced_mesh_part_id(owner, index)))
            }
            let rawCorners = UnsafeBufferPointer(start: corners, count: counts.corners).map {
                RawMeshSourceCorner(
                    kind: $0.kind.rawValue, firstInfluence: $0.first_influence, influenceCount: $0.influence_count)
            }
            try Task.checkCancellation()
            let rawInfluences = UnsafeBufferPointer(start: influences, count: counts.influences).map {
                RawMeshSourceInfluence(kind: $0.kind.rawValue, sourceIndex: $0.source_index, weight: $0.weight)
            }
            return try MeshSourceHints(
                identities: identities, corners: rawCorners, influences: rawInfluences,
                expandedVertexCount: counts.expandedVertices)
        } catch let cause as MeshSourceDataError {
            throw MeshLoadingError(status: 3, message: "The engine returned invalid source hints: \(cause).")
        }
    }
}
