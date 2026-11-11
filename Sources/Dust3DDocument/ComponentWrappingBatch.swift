import Foundation

/// An explicit wrapping edit across selected groups.
public enum ComponentWrappingEdit: Sendable {
    /// Replace body-weight references using one common owner/descendant exclusion plan.
    case binding(ComponentWrapBindingChoice)
    case mode(ComponentWrapMode)
    /// Turn wrapping off and remove the group’s saved wrapping overrides.
    case clearSettings
    case scalar(ComponentWrappingScalarProperty, Double)
    case keepChildren(Bool)
    case targetFaces(Int)
    case surfacePattern(ComponentSurfacePattern)
    case surfaceScalar(ComponentSurfaceScalar, Double)
    case surfaceInk(DocumentColor?)

    /// Finish edits refresh baked pixels without changing the displayed geometry.
    public var isSurfaceOnly: Bool {
        switch self {
        case .surfacePattern, .surfaceScalar, .surfaceInk: return true
        default: return false
        }
    }
}

/// Preflight once, mutate one owned DOM, and preserve each owner's defaults independently.
enum ComponentWrappingBatch {
    static func apply(_ model: XMLDocument, ids: [String], edit: ComponentWrappingEdit) throws -> Bool {
        guard ids.count <= ComponentHierarchy.maximumCount else { throw DocumentError.limitExceeded }
        guard !ids.isEmpty else {
            throw DocumentError.invalidComponentWrapping
        }
        let selected = Set(ids.map { Data($0.utf8) })
        guard selected.count == ids.count else { throw DocumentError.invalidComponentWrapping }
        let components = try ComponentHierarchy.read(model)
        let indexed = Dictionary(uniqueKeysWithValues: components.map { (Data($0.id.utf8), $0) })
        for id in ids {
            guard let row = indexed[Data(id.utf8)] else { throw DocumentError.missingComponent(id) }
            guard row.isGroup else { throw DocumentError.invalidComponentWrapping }
        }
        if case .binding(let choice) = edit {
            let plan = try ComponentWrapBindingPlan(components: components, ownerIDs: Set(ids))
            guard plan.allows(choice) else { throw DocumentError.invalidComponentWrapBinding }
        }
        let elements = PartSplitting.componentElements(model)
        var updates: [(XMLElement, String, String?)] = []
        for element in elements {
            guard let id = element.attribute(forName: "id")?.stringValue, selected.contains(Data(id.utf8)) else {
                continue
            }
            let current = ComponentWrapping.read(element)
            let name: String
            let replacement: String?
            switch edit {
            case .clearSettings:
                for attribute in element.attributes ?? [] {
                    guard let name = attribute.name, name.hasPrefix("wrap"),
                        attribute.prefix?.isEmpty != false, attribute.uri?.isEmpty != false
                    else { continue }
                    updates.append((element, name, nil))
                }
                continue
            case .binding(let choice):
                guard !ComponentWrapBindingXML.isUnchanged(current.binding, choice: choice) else { continue }
                name = "wrapBindTo"
                replacement = ComponentWrapBindingXML.targetID(for: choice)
            case .mode(let mode):
                guard current.mode != mode else { continue }
                name = "wrap"
                replacement = mode == .none ? nil : mode.rawValue
            case .scalar(let property, let value):
                guard EngineScalar.isValid(value, in: property.bounds) else {
                    throw DocumentError.invalidComponentWrapping
                }
                guard current.scalarValue(property) != value else { continue }
                name = property.rawValue
                replacement = String(value)
            case .keepChildren(let value):
                guard current.keepsChildren != value else { continue }
                name = "wrapKeep"
                replacement = value ? "true" : "false"
            case .targetFaces(let value):
                guard (64...20000).contains(value) else { throw DocumentError.invalidComponentWrapping }
                guard current.targetFaces != value else { continue }
                name = "wrapFaces"
                replacement = String(value)
            case .surfacePattern(let pattern):
                guard current.surfaceDetails.pattern != pattern else { continue }
                name = "wrapPattern"
                replacement = pattern == .none ? nil : pattern.rawValue
            case .surfaceScalar(let property, let value):
                guard EngineScalar.isValid(value, in: property.bounds) else {
                    throw DocumentError.invalidComponentWrapping
                }
                guard current.surfaceDetails.scalarValue(property) != value else { continue }
                name = property.rawValue
                replacement = value == property.defaultValue ? nil : String(value)
            case .surfaceInk(let color):
                guard color == nil || color?.alpha == 255 else { throw DocumentError.invalidComponentWrapping }
                guard current.surfaceDetails.ink != color.map(ComponentColorValue.value) ?? .unset else { continue }
                name = "wrapPatternColor"
                replacement = color?.archiveValue
            }
            updates.append((element, name, replacement))
        }
        try Task.checkCancellation()
        for (element, name, value) in updates {
            element.removeAttribute(forName: name)
            if let value {
                let attribute = XMLNode(kind: .attribute)
                attribute.name = name
                attribute.stringValue = value
                element.addAttribute(attribute)
            }
        }
        return !updates.isEmpty
    }
}
