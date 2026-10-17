import Foundation

/// Inherited built-in cross-section presets, using their serialized names.
public enum CutFacePreset: String, CaseIterable, Hashable, Sendable {
    /// Four-sided cross-section; the inherited default.
    case quad = "Quad"
    /// Five-sided cross-section.
    case pentagon = "Pentagon"
    /// Six-sided cross-section.
    case hexagon = "Hexagon"
    /// Three-sided cross-section.
    case triangle = "Triangle"
}

/// A procedural cross-section preset or the exact archive identity of a profile part.
public enum CutFaceSelection: Hashable, Sendable {
    /// Use a built-in cross-section template.
    case preset(CutFacePreset)
    /// Read the profile from an existing part, without normalizing or rewriting its identity.
    case linkedPart(String)
}

enum PartCutFace {
    static func selection(_ element: XMLElement) -> CutFaceSelection? {
        let text = element.attribute(forName: "cutFace")?.stringValue ?? ""
        if text.isEmpty { return .preset(.quad) }
        if let preset = CutFacePreset(rawValue: text) { return .preset(preset) }
        if CutFaceLinks.canonicalID(text) != nil { return .linkedPart(text) }
        return nil
    }

    static func rotation(_ element: XMLElement) -> Double? {
        let text = element.attribute(forName: "cutRotation")?.stringValue ?? ""
        if text.isEmpty { return 0 }
        return EngineScalar.parse(text, in: -1...1)
    }

    static func setSelection(_ model: XMLDocument, parts: [DocumentPart], id: String, selection: CutFaceSelection)
        throws -> Bool
    {
        let (current, element) = try part(model, parts: parts, id: id)
        let text: String?
        switch selection {
        case .preset(let preset): text = preset == .quad ? nil : preset.rawValue
        case .linkedPart(let target):
            guard CutFaceLinks.canonicalID(target) != nil else { throw DocumentError.invalidPartCutFace }
            guard parts.contains(where: { $0.id == target }) else { throw DocumentError.missingPart(target) }
            text = target
        }
        guard current.cutFace != selection else { return false }
        replaceAttribute(element, name: "cutFace", value: text)
        if case .linkedPart(let target) = selection {
            let root = model.rootElement()
            try PartJoining.validateProfileLink(
                from: id, to: target,
                parts: DocumentXML.childElements(DocumentXML.childElements(root, named: "parts").first, named: "part"),
                nodes: DocumentXML.childElements(DocumentXML.childElements(root, named: "nodes").first, named: "node"))
        }
        return true
    }

    static func setRotation(_ model: XMLDocument, parts: [DocumentPart], id: String, rotation: Double) throws -> Bool {
        guard EngineScalar.isValid(rotation, in: -1...1) else { throw DocumentError.invalidPartCutRotation }
        let (current, element) = try part(model, parts: parts, id: id)
        guard current.cutRotation != rotation else { return false }
        // Retain fine rotations that the inherited writer omits within 0.01 of zero.
        replaceAttribute(element, name: "cutRotation", value: rotation == 0 ? nil : String(rotation))
        return true
    }

    private static func part(_ model: XMLDocument, parts: [DocumentPart], id: String) throws -> (
        DocumentPart, XMLElement
    ) {
        guard let current = parts.first(where: { $0.id == id }),
            let element = DocumentXML.childElements(model.rootElement(), named: "parts").first?
                .elements(forName: "part").first(where: { $0.attribute(forName: "id")?.stringValue == id })
        else { throw DocumentError.missingPart(id) }
        return (current, element)
    }

    private static func replaceAttribute(_ element: XMLElement, name: String, value: String?) {
        element.removeAttribute(forName: name)
        guard let value else { return }
        let attribute = XMLNode(kind: .attribute)
        attribute.name = name
        attribute.stringValue = value
        element.addAttribute(attribute)
    }
}
