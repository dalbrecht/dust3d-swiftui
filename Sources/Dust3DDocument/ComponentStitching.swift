import Foundation

/// Component stitching closure flags using inherited archive names; absent flags are false.
public enum ComponentStitchingClosureProperty: String, CaseIterable, Hashable, Sendable {
    /// Close the first stitching-line end profile.
    case front = "frontClosed"
    /// Close the last line end profile, or enable the loop back cap.
    case back = "backClosed"
    /// Join each stitching spline's own endpoints.
    case side = "sideClosed"
}

/// Loop-cap parameters, retaining fine values supported by the engine Float.
public enum ComponentStitchingScalarProperty: String, CaseIterable, Hashable, Sendable {
    /// Loop back-cap depth relative to the outer boundary radius.
    case depthRatio = "backCloseDepthRatio"
    /// Loop back-cap shape blend, from smooth to sharp.
    case sharpness = "backCloseSharpness"

    /// Inherited value when the attribute is absent.
    public var defaultValue: Double { self == .depthRatio ? 1 : 0 }
    /// Supported editing range; depth is 0...2 and sharpness is 0...1.
    public var bounds: ClosedRange<Double> { self == .depthRatio ? 0...2 : 0...1 }
}

/// Read-only stitching interpretation. Nil values preserve unsupported or ambiguous source metadata.
public struct ComponentStitchingSettings: Equatable, Sendable {
    /// Target segments in 0...100; absent means automatic (zero), unsupported spellings are nil.
    public let targetSegments: Int?
    private let closures: [ComponentStitchingClosureProperty: Bool]
    private let scalars: [ComponentStitchingScalarProperty: Double]

    /// Read a known closure flag; absent means false and unsupported text returns nil.
    /// - Parameter property: Front, back or side closure.
    /// - Returns: The supported source value without modifying the archive.
    /// - Example: `component.stitching.closureValue(.front)`.
    public func closureValue(_ property: ComponentStitchingClosureProperty) -> Bool? { closures[property] }
    /// Read a bounded loop-cap parameter retained by the engine Float.
    /// - Parameter property: Depth ratio or sharpness.
    /// - Returns: The known source/default value, or nil for unsupported metadata.
    /// - Example: `component.stitching.scalarValue(.depthRatio)`.
    public func scalarValue(_ property: ComponentStitchingScalarProperty) -> Double? { scalars[property] }

    init(
        closures: [ComponentStitchingClosureProperty: Bool], scalars: [ComponentStitchingScalarProperty: Double],
        targetSegments: Int?
    ) {
        self.closures = closures
        self.scalars = scalars
        self.targetSegments = targetSegments
    }
}

/// One explicit stitching value applied to all captured groups.
public enum ComponentStitchingEdit: Sendable {
    case closure(ComponentStitchingClosureProperty, Bool)
    case segments(Int)
    case scalar(ComponentStitchingScalarProperty, Double)
}

package struct ComponentStitchingBatchSupport: Sendable {
    package let line: Bool
    package let loop: Bool
    package let back: Bool

    package init(groups: [DocumentComponent], components: [DocumentComponent], parts: [DocumentPart]) {
        guard groups.count > 1, groups.allSatisfy(\.isGroup) else {
            (line, loop, back) = (false, false, false)
            return
        }
        let roles = Dictionary(
            uniqueKeysWithValues: parts.compactMap { part in
                part.target.map { (Data(part.id.utf8), $0) }
            })
        let links = Dictionary(
            uniqueKeysWithValues: components.compactMap { component in
                component.partID.map { (Data(component.id.utf8), Data($0.utf8)) }
            })
        let families = groups.map { group in
            Set(group.childIDs.compactMap { links[Data($0.utf8)].flatMap { roles[$0] } })
        }
        line = families.allSatisfy { $0.contains(.stitchingLine) }
        loop = families.allSatisfy { $0.contains(.stitchingLoop) }
        back = families.allSatisfy { $0.contains(.stitchingLine) || $0.contains(.stitchingLoop) }
    }

    package func permits(_ edit: ComponentStitchingEdit) -> Bool {
        switch edit {
        case .closure(.back, _): back
        case .closure, .segments: line
        case .scalar: loop
        }
    }
}

enum ComponentStitching {
    static func read(_ element: XMLElement) -> ComponentStitchingSettings {
        var closures: [ComponentStitchingClosureProperty: Bool] = [:]
        for property in ComponentStitchingClosureProperty.allCases {
            let text = element.attribute(forName: property.rawValue)?.stringValue ?? ""
            if ["true", "True", "1"].contains(text) {
                closures[property] = true
            } else if ["false", "False", "0", ""].contains(text) {
                closures[property] = false
            }
        }
        var scalars: [ComponentStitchingScalarProperty: Double] = [:]
        for property in ComponentStitchingScalarProperty.allCases {
            if let text = element.attribute(forName: property.rawValue)?.stringValue {
                scalars[property] = EngineScalar.parse(text, in: property.bounds)
            } else {
                scalars[property] = property.defaultValue
            }
        }
        let segments: Int?
        if let text = element.attribute(forName: "targetSegments")?.stringValue {
            segments = Int(text).flatMap { (0...100).contains($0) ? $0 : nil }
        } else {
            segments = 0
        }
        return ComponentStitchingSettings(closures: closures, scalars: scalars, targetSegments: segments)
    }

    static func setClosure(_ model: XMLDocument, id: String, property: ComponentStitchingClosureProperty, value: Bool)
        throws -> Bool
    {
        let (current, element) = try component(model, id: id)
        guard current.stitching.closureValue(property) != value else { return false }
        replace(element, name: property.rawValue, value: value ? "true" : nil)
        return true
    }

    static func setScalar(_ model: XMLDocument, id: String, property: ComponentStitchingScalarProperty, value: Double)
        throws -> Bool
    {
        guard EngineScalar.isValid(value, in: property.bounds) else {
            throw DocumentError.invalidComponentStitchingScalar
        }
        let (current, element) = try component(model, id: id)
        guard current.stitching.scalarValue(property) != value else { return false }
        replace(element, name: property.rawValue, value: value == property.defaultValue ? nil : String(value))
        return true
    }

    static func setSegments(_ model: XMLDocument, id: String, segments: Int) throws -> Bool {
        guard (0...100).contains(segments) else { throw DocumentError.invalidComponentTargetSegments }
        let (current, element) = try component(model, id: id)
        guard current.stitching.targetSegments != segments else { return false }
        replace(element, name: "targetSegments", value: segments == 0 ? nil : String(segments))
        return true
    }

    static func setBatch(
        _ model: XMLDocument, parts: [DocumentPart], ids: [String], edit: ComponentStitchingEdit
    ) throws -> Bool {
        guard ids.count <= ComponentHierarchy.maximumCount else { throw DocumentError.limitExceeded }
        let keys = Set(ids.map { Data($0.utf8) })
        guard keys.count == ids.count else { throw DocumentError.invalidComponentStructure }
        let components = try ComponentHierarchy.read(model)
        let groups = components.filter { keys.contains(Data($0.id.utf8)) }
        guard groups.count == ids.count,
            ComponentStitchingBatchSupport(groups: groups, components: components, parts: parts).permits(edit)
        else { throw DocumentError.invalidComponentStructure }
        let elements = Dictionary(
            uniqueKeysWithValues: PartSplitting.componentElements(model).compactMap { element in
                element.attribute(forName: "id")?.stringValue.map { (Data($0.utf8), element) }
            })
        let update: (name: String, value: String?)
        switch edit {
        case .closure(let property, let value):
            update = (property.rawValue, value ? "true" : nil)
        case .segments(let segments):
            guard (0...100).contains(segments) else { throw DocumentError.invalidComponentTargetSegments }
            update = ("targetSegments", segments == 0 ? nil : String(segments))
        case .scalar(let property, let value):
            guard EngineScalar.isValid(value, in: property.bounds) else {
                throw DocumentError.invalidComponentStitchingScalar
            }
            update = (property.rawValue, value == property.defaultValue ? nil : String(value))
        }
        var changed = false
        for group in groups {
            try Task.checkCancellation()
            guard let element = elements[Data(group.id.utf8)] else { throw DocumentError.invalidComponentStructure }
            let isCurrent: Bool
            switch edit {
            case .closure(let property, let value): isCurrent = group.stitching.closureValue(property) == value
            case .segments(let segments): isCurrent = group.stitching.targetSegments == segments
            case .scalar(let property, let value): isCurrent = group.stitching.scalarValue(property) == value
            }
            guard !isCurrent else { continue }
            replace(element, name: update.name, value: update.value)
            changed = true
        }
        return changed
    }

    private static func component(_ model: XMLDocument, id: String) throws -> (DocumentComponent, XMLElement) {
        guard let current = try ComponentHierarchy.read(model).first(where: { $0.id == id }),
            let element = PartSplitting.componentElements(model).first(where: {
                $0.attribute(forName: "id")?.stringValue == id
            })
        else { throw DocumentError.missingComponent(id) }
        return (current, element)
    }

    private static func replace(_ element: XMLElement, name: String, value: String?) {
        element.removeAttribute(forName: name)
        guard let value else { return }
        let attribute = XMLNode(kind: .attribute)
        attribute.name = name
        attribute.stringValue = value
        element.addAttribute(attribute)
    }
}
