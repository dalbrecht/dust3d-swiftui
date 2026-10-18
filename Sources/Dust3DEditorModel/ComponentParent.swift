import Foundation

/// Explicit root/group destinations avoid using a missing selection as an implicit root move.
public enum ComponentParent: Hashable, Sendable {
    case root
    case component(String)

    /// Document command parent identity; nil explicitly denotes the root container.
    public var componentID: String? {
        switch self {
        case .root: return nil
        case .component(let id): return id
        }
    }
}

/// A supported destination presented in unchanged document order.
public struct ComponentParentOption: Identifiable, Equatable, Sendable {
    public let id: ComponentParent
    public let title: String
}
