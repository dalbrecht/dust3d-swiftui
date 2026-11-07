import Foundation

/// Mirror is independent of the cross-section modifier enumeration and its maintained native fixtures.
enum PartMirrorMetadata {
    static func value(_ element: XMLElement) -> Bool? {
        guard let text = element.attribute(forName: "xMirrored")?.stringValue else { return false }
        if ["true", "True", "1"].contains(text) { return true }
        if ["false", "False", "0", ""].contains(text) { return false }
        return nil
    }
    static func set(_ model: XMLDocument, contents: DocumentContents, origin: NodePosition?, id: String, value: Bool)
        throws -> Bool
    {
        guard let part = contents.parts.first(where: { $0.id.utf8.elementsEqual(id.utf8) }),
            let element = model.rootElement()?.elements(forName: "parts").first?.elements(forName: "part").first(
                where: { $0.attribute(forName: "id")?.stringValue?.utf8.elementsEqual(id.utf8) == true })
        else { throw DocumentError.missingPart(id) }
        guard part.target == .model else { throw DocumentError.invalidPartMirrorRole }
        guard part.xMirrored != value else { return false }
        // This initialization belongs to the mirror command, not generic axis-constrained origin editing.
        if origin == nil, let root = model.rootElement() {
            let center = try DocumentOriginSettlement.center(of: contents.nodes.map(\.value))
            replace(root, name: "originX", value: String(center.x))
            replace(root, name: "originY", value: String(center.y))
            replace(root, name: "originZ", value: String(center.z))
        }
        replace(element, name: "xMirrored", value: value ? "true" : nil)
        return true
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
