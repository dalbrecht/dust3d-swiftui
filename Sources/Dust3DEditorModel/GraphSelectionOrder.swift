import Foundation

/// Explicit identity supply for one selected edge in a pure state midpoint transaction.
public struct EdgeMidpointIdentity: Sendable {
    public let originalEdgeID: String
    public let nodeID: String
    public let edgeID: String

    /// Supply fresh node/second-edge identities for one captured original edge.
    public init(originalEdgeID: String, nodeID: String, edgeID: String) {
        self.originalEdgeID = originalEdgeID
        self.nodeID = nodeID
        self.edgeID = edgeID
    }
}

/// Qt sorts Uuid bodies; native named identities keep deterministic byte order as a compatibility fallback.
enum GraphSelectionOrder {
    static func sorted(_ ids: Set<String>) -> [String] {
        func key(_ id: String) -> Substring {
            let bytes = Array(id.utf8)
            if bytes.count == 38, bytes.first == 123 { return id.dropFirst().dropLast() }
            return id[...]
        }
        return ids.sorted { key($0).utf8.lexicographicallyPrecedes(key($1).utf8) }
    }
}
