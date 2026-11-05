import Foundation

/// Explicit wrapper removal cannot silently change opaque payload's inherited XML context.
public enum ComponentUngroupError: Error, Equatable, Sendable {
    case inheritedContext(componentID: String, attribute: String)
    case textNamespaceContext(componentID: String)
}

/// Metadata-only eligibility shared by document transactions and snapshot UI; no XML is parsed by UI.
public struct ComponentUngroupPlan: Sendable {
    public static let maximumCount = ComponentHierarchy.maximumCount
    /// Every explicit eligible wrapper, including selected descendants, in source order.
    public let wrapperIDs: [String]

    /// Validate every raw request before exact UTF-8 deduplication. Empty and leaf-only requests are no-ops.
    /// Loaded linked/opaque wrappers with component children and supported extension-only groups are eligible.
    public init(components: [DocumentComponent], ids: [String]) throws {
        guard components.count <= Self.maximumCount, ids.count <= Self.maximumCount else {
            throw DocumentError.limitExceeded
        }
        guard Set(components.map(\.id)).count == components.count else { throw DocumentError.invalidComponent }
        let available = Set(components.map { Data($0.id.utf8) })
        for id in ids where !available.contains(Data(id.utf8)) { throw DocumentError.missingComponent(id) }
        let selected = Set(ids.map { Data($0.utf8) })
        wrapperIDs = components.filter {
            selected.contains(Data($0.id.utf8)) && (!$0.childIDs.isEmpty || ($0.isGroup && $0.hasChildXML))
        }.map(\.id)
    }
}
