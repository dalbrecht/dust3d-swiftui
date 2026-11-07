import Foundation

/// Mirror is independent of the cross-section modifier enumeration and its maintained native fixtures.
enum PartMirrorMetadata {
    static func value(_ element: XMLElement) -> Bool? {
        guard let text = element.attribute(forName: "xMirrored")?.stringValue else { return false }
        if ["true", "True", "1"].contains(text) { return true }
        if ["false", "False", "0", ""].contains(text) { return false }
        return nil
    }
    static func set(_ root: XMLElement, contents: DocumentContents, id: String, value: Bool) throws -> Bool {
        guard let part = contents.parts.first(where: { $0.id.utf8.elementsEqual(id.utf8) }),
            let element = root.elements(forName: "parts").first?.elements(forName: "part").first(
                where: { $0.attribute(forName: "id")?.stringValue?.utf8.elementsEqual(id.utf8) == true })
        else { throw DocumentError.missingPart(id) }
        guard part.target == .model else { throw DocumentError.invalidPartMirrorRole }
        guard part.xMirrored != value else { return false }
        if value {
            try ensureOrigin(in: root, nodes: contents.nodes)
        }
        replace(element, name: "xMirrored", value: value ? "true" : nil)
        return true
    }
    private static func ensureOrigin(in root: XMLElement, nodes: [DocumentNode]) throws {
        let names = ["originX", "originY", "originZ"]
        let attributes = names.compactMap { root.attribute(forName: $0) }
        if attributes.isEmpty {
            let center = try DocumentOriginSettlement.center(of: nodes.map(\.value))
            for (name, coordinate) in zip(names, [center.x, center.y, center.z]) {
                replace(root, name: name, value: String(coordinate))
            }
        } else {
            guard attributes.count == names.count,
                attributes.allSatisfy({
                    EngineScalar.parseArchiveDouble($0.stringValue ?? "", in: -1_000_000...1_000_000) != nil
                })
            else { throw DocumentError.invalidPartMirrorOrigin }
        }
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
