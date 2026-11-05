import Foundation

/// One explicit field replacement across selected groups, without changing their other settings.
public enum ComponentWrappingEdit: Sendable {
    case mode(ComponentWrapMode)
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
        let selected = Set(ids)
        guard selected.count == ids.count else { throw DocumentError.invalidComponentWrapping }
        let components = try ComponentHierarchy.read(model)
        let indexed = Dictionary(uniqueKeysWithValues: components.map { ($0.id, $0) })
        for id in ids {
            guard let row = indexed[id] else { throw DocumentError.missingComponent(id) }
            guard row.isGroup else { throw DocumentError.invalidComponentWrapping }
        }
        let elements = PartSplitting.componentElements(model)
        var updates: [(XMLElement, String, String?)] = []
        for element in elements {
            guard let id = element.attribute(forName: "id")?.stringValue, selected.contains(id) else { continue }
            let current = ComponentWrapping.read(element)
            let name: String
            let replacement: String?
            switch edit {
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
                replacement = current.mode.map { property.defaultValue(for: $0) == value } == true ? nil : String(value)
            case .keepChildren(let value):
                guard current.keepsChildren != value else { continue }
                name = "wrapKeep"
                replacement = current.mode.map { ($0 == .cloth) == value } == true ? nil : value ? "true" : "false"
            case .targetFaces(let value):
                guard (64...20000).contains(value) else { throw DocumentError.invalidComponentWrapping }
                guard current.targetFaces != value else { continue }
                name = "wrapFaces"
                replacement = current.mode.map { ($0 == .cloth ? 1200 : 1600) == value } == true ? nil : String(value)
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
