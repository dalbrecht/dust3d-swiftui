import Foundation

/// Procedural roles supported by the native modeling editor, using inherited archive spellings.
/// ImportedModel requires the separate embedded-model pipeline and remains unsupported metadata here.
public enum PartTarget: String, CaseIterable, Sendable {
    /// Produce ordinary tube geometry.
    case model = "Model"
    /// Supply a cross-section profile without contributing ordinary joined geometry.
    case cutFace = "CutFace"
    /// Supply an ordered line to component stitching.
    case stitchingLine = "StitchingLine"
    /// Supply a closed boundary to component stitching.
    case stitchingLoop = "StitchingLoop"
}

enum PartTargetMetadata {
    static func value(_ element: XMLElement) -> PartTarget? {
        let text = element.attribute(forName: "target")?.stringValue ?? ""
        return text.isEmpty ? .model : PartTarget(rawValue: text)
    }

    static func set(_ model: XMLDocument, parts: [DocumentPart], id: String, target: PartTarget) throws -> Bool {
        guard let current = parts.first(where: { $0.id == id }),
            let element = DocumentXML.childElements(model.rootElement(), named: "parts").first?
                .elements(forName: "part").first(where: { $0.attribute(forName: "id")?.stringValue == id })
        else { throw DocumentError.missingPart(id) }
        guard current.target != target else { return false }
        element.removeAttribute(forName: "target")
        if target != .model {
            let attribute = XMLNode(kind: .attribute)
            attribute.name = "target"
            attribute.stringValue = target.rawValue
            element.addAttribute(attribute)
        }
        return true
    }
}
