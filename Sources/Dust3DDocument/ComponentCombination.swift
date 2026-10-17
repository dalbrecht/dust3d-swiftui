import Foundation

/// Upstream component combination operations, serialized using their inherited XML names.
public enum ComponentCombineMode: String, CaseIterable, Sendable {
    /// Union this component with the preceding combined geometry.
    case normal = "Normal"
    /// Subtract this component from preceding combined geometry.
    case inversion = "Inversion"
    /// Retain this component separately from boolean combination.
    case uncombined = "Uncombined"
}

enum ComponentCombination {
    static func mode(_ element: XMLElement) -> ComponentCombineMode? {
        let text = element.attribute(forName: "combineMode")?.stringValue ?? ""
        let mode = text.isEmpty ? ComponentCombineMode.normal : ComponentCombineMode(rawValue: text)
        let inverse = element.attribute(forName: "inverse")?.stringValue ?? ""
        if mode == .normal, ["true", "True", "1"].contains(inverse) { return .inversion }
        return mode
    }

    static func set(_ model: XMLDocument, id: String, mode: ComponentCombineMode) throws -> Bool {
        let components = try ComponentHierarchy.read(model)
        guard let component = components.first(where: { $0.id == id }),
            let element = PartSplitting.componentElements(model).first(where: {
                $0.attribute(forName: "id")?.stringValue == id
            })
        else { throw DocumentError.missingComponent(id) }
        guard component.combineMode != mode else { return false }
        // Legacy inversion overrides Normal in the engine; remove it only when the user explicitly changes mode.
        element.removeAttribute(forName: "inverse")
        element.removeAttribute(forName: "combineMode")
        let attribute = XMLNode(kind: .attribute)
        attribute.name = "combineMode"
        attribute.stringValue = mode.rawValue
        element.addAttribute(attribute)
        return true
    }
}
