import Foundation

/// One component in XML preorder. Parent/child identities preserve the upstream nested hierarchy.
/// Unknown link kinds remain available without being interpreted as part references.
public struct DocumentComponent: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    /// Explicit source color, absent override, or unsupported original text.
    public let color: ComponentColorValue
    /// Exact color-image identity, missing override or unsupported original source text.
    public let colorImage: ComponentColorImageValue
    /// Nonempty legacy wrapPattern/wrapWrinkles metadata whose surface rendering is not established by an image bake.
    public let hasLegacySurfaceDetails: Bool
    /// Effective known mode, including legacy component inversion; nil preserves an unknown source mode.
    public let combineMode: ComponentCombineMode?
    /// Normal smoothing cutoff in 0–180 degrees, zero when absent; nil preserves unsupported source values.
    public let smoothCutoffDegrees: Double?
    /// Lossless interpretation of wrapping geometry parameters.
    public let wrapping: ComponentWrappingSettings
    /// Lossless, opt-in interpretation of component stitching flags and parameters.
    public let stitching: ComponentStitchingSettings
    public let parentID: String?
    public let childIDs: [String]
    /// Actual child XML, including opaque elements, comments and text rather than only component identities.
    public let hasChildXML: Bool
    public let linkDataType: String?
    public let linkData: String?
    /// Qt stores the equipment assignment after the final space-at marker.
    public var equipmentSlot: String? {
        equipmentMarker.map { String(name[$0.upperBound...]) }
    }

    var equipmentBaseName: String {
        equipmentMarker.map { String(name[..<$0.lowerBound]) } ?? name
    }

    private var equipmentMarker: Range<String.Index>? {
        name.range(of: " @", options: .backwards)
    }

    /// A supported unlinked group, including an empty group. Unknown links remain opaque.
    public var isGroup: Bool { (linkDataType ?? "").isEmpty && (linkData ?? "").isEmpty }
    public var partID: String? { linkDataType == "partId" ? linkData : nil }
}

/// Component interpretation is opt-in: opaque hierarchies remain preservable by unrelated edits.
enum ComponentHierarchy {
    static let maximumCount = 10_000
    static func read(_ model: XMLDocument) throws -> [DocumentComponent] {
        let containers = DocumentXML.childElements(model.rootElement(), named: "components")
        guard containers.count <= 1 else { throw DocumentError.invalidComponent }
        let elements = PartSplitting.componentElements(model)
        guard elements.count <= maximumCount else { throw DocumentError.limitExceeded }
        // Upstream interprets any child tag with an ID as a component. Reject unknown tagged
        // identities rather than presenting a tree that silently omits generator input.
        for parent in containers + elements {
            for child in parent.children ?? [] {
                if let child = child as? XMLElement, child.name != "component",
                    child.attribute(forName: "id") != nil
                {
                    throw DocumentError.invalidComponent
                }
            }
        }
        var identities = Set<String>()
        var result: [DocumentComponent] = []
        for element in elements {
            guard let id = element.attribute(forName: "id")?.stringValue, !id.isEmpty,
                identities.insert(id).inserted
            else { throw DocumentError.invalidComponent }
            let parent = element.parent as? XMLElement
            result.append(
                DocumentComponent(
                    id: id,
                    name: element.attribute(forName: "name")?.stringValue ?? "",
                    color: ComponentColorValue.read(element),
                    colorImage: ComponentColorImageValue.read(element),
                    hasLegacySurfaceDetails: ["wrapPattern", "wrapWrinkles"].contains {
                        !(element.attribute(forName: $0)?.stringValue ?? "").isEmpty
                    },
                    combineMode: ComponentCombination.mode(element),
                    smoothCutoffDegrees: ComponentSmoothing.degrees(element),
                    wrapping: ComponentWrapping.read(element),
                    stitching: ComponentStitching.read(element),
                    parentID: parent?.name == "component" ? parent?.attribute(forName: "id")?.stringValue : nil,
                    childIDs: DocumentXML.childElements(element, named: "component").compactMap {
                        $0.attribute(forName: "id")?.stringValue
                    },
                    hasChildXML: !(element.children ?? []).isEmpty,
                    linkDataType: element.attribute(forName: "linkDataType")?.stringValue,
                    linkData: element.attribute(forName: "linkData")?.stringValue))
        }
        return result
    }

    static func rename(_ model: XMLDocument, id: String, name: String) throws -> Bool {
        try validateName(name)
        let components = try read(model)
        guard let component = components.first(where: { $0.id == id }),
            let element = PartSplitting.componentElements(model).first(where: {
                $0.attribute(forName: "id")?.stringValue == id
            })
        else { throw DocumentError.missingComponent(id) }
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard component.name != value else { return false }
        writeName(value, on: element)
        return true
    }

    static func setEquipmentSlot(_ model: XMLDocument, parts: [DocumentPart], id: String, slot: String) throws -> Bool {
        let components = try read(model)
        guard let component = components.first(where: { $0.id.utf8.elementsEqual(id.utf8) }),
            let element = PartSplitting.componentElements(model).first(where: {
                $0.attribute(forName: "id")?.stringValue?.utf8.elementsEqual(id.utf8) == true
            })
        else { throw DocumentError.missingComponent(id) }
        guard let partID = component.partID,
            parts.first(where: { $0.id.utf8.elementsEqual(partID.utf8) })?.target == .model
        else { throw DocumentError.invalidComponent }
        let value = slot.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = value.isEmpty ? component.equipmentBaseName : component.equipmentBaseName + " @" + value
        guard !component.name.utf8.elementsEqual(name.utf8) else { return false }
        try validateName(name)
        writeName(name, on: element)
        return true
    }

    private static func validateName(_ name: String) throws {
        guard name.utf8.count <= 1024,
            name.unicodeScalars.allSatisfy({
                $0.value != 0xFFFE && $0.value != 0xFFFF && !CharacterSet.controlCharacters.contains($0)
                    && !CharacterSet.newlines.contains($0)
            })
        else { throw DocumentError.invalidComponentName }
    }

    private static func writeName(_ value: String, on element: XMLElement) {
        element.removeAttribute(forName: "name")
        if !value.isEmpty {
            let attribute = XMLNode(kind: .attribute)
            attribute.name = "name"
            attribute.stringValue = value
            element.addAttribute(attribute)
        }
    }
}
