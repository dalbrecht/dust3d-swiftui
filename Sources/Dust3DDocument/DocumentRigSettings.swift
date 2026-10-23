import Foundation

/// Inherited template names, describing stored intent rather than native generation capability.
public enum DocumentRigType: String, CaseIterable, Sendable {
    case disabled = "None"
    case biped = "Biped"
    case quadruped = "Quadruped"
    case bird = "Bird"
    case fish = "Fish"
    case snake = "Snake"
    case insect = "Insect"
    case spider = "Spider"
}

/// Immutable canvas rig parameters. Reading never generates a skeleton or changes source bytes.
public struct DocumentRigSettings: Sendable, Equatable {
    /// Recognized template, or nil for unsupported source intent.
    public let rigType: DocumentRigType?
    /// Exact original attribute, including unsupported spellings; nil means absent.
    public let sourceRigType: String?
    /// Inherited truth semantics: true, True and 1 enable eyelids; other strings disable them.
    public let headHasEyelids: Bool

    init(root: XMLElement?) {
        sourceRigType = root?.attribute(forName: "rigType")?.stringValue
        let text = sourceRigType ?? ""
        rigType = text.isEmpty ? .disabled : DocumentRigType(rawValue: text)
        headHasEyelids = ["true", "True", "1"].contains(
            root?.attribute(forName: "headHasEyelids")?.stringValue ?? "")
    }
}

enum DocumentRigMetadata {
    static func set(root: XMLElement, name: String, value: String?) {
        root.removeAttribute(forName: name)
        guard let value else { return }
        let attribute = XMLNode(kind: .attribute)
        attribute.name = name
        attribute.stringValue = value
        root.addAttribute(attribute)
    }
}
