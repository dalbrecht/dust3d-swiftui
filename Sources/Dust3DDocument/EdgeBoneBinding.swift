import Foundation

enum EdgeBoneBinding {
    static func set(model: XMLDocument, contents: DocumentContents, id: String, name: String) throws -> Bool {
        guard name.utf8.count <= 1024,
            name.unicodeScalars.allSatisfy({
                !CharacterSet.controlCharacters.contains($0) && !CharacterSet.newlines.contains($0)
                    && $0.value != 0xFFFE && $0.value != 0xFFFF
            })
        else { throw DocumentError.invalidBoneName }
        let editable = Set(contents.nodes.filter(\.isEditable).map(\.id))
        guard let current = contents.edges.first(where: { $0.id == id }),
            editable.contains(current.fromID), editable.contains(current.toID),
            let edge = model.rootElement()?.elements(forName: "edges").first?.elements(forName: "edge")
                .first(where: { $0.attribute(forName: "id")?.stringValue == id })
        else { throw DocumentError.invalidNode }
        // Bone names are exact template lookup identities; trimming would silently retarget a binding.
        guard !current.hasExactBoneName(name) else { return false }
        edge.removeAttribute(forName: "boneName")
        if !name.isEmpty {
            let attribute = XMLNode(kind: .attribute)
            attribute.name = "boneName"
            attribute.stringValue = name
            edge.addAttribute(attribute)
        }
        return true
    }
}
