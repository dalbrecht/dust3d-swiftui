import Foundation

/// Supported part-state attributes, using the inherited XML names.
public enum PartStateProperty: String, CaseIterable, Sendable {
    case visible
    case locked
    case disabled
}

/// Immutable part metadata in source order. Visibility affects editing; disabled also excludes generation.
public struct DocumentPart: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let title: String
    public let isVisible: Bool
    public let isLocked: Bool
    public let isDisabled: Bool
    public var isEditVisible: Bool { isVisible && !isDisabled }
    public var isEditable: Bool { isEditVisible && !isLocked }

    init(id: String, name: String, index: Int, isVisible: Bool, isLocked: Bool, isDisabled: Bool) {
        self.id = id
        self.name = name
        self.title = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Part \(index + 1)" : name
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.isDisabled = isDisabled
    }
}
