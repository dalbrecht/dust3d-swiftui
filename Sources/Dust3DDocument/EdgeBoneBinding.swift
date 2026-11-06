import Foundation

enum EdgeBoneBinding {
    static func set(model: XMLDocument, contents: DocumentContents, id: String, name: String) throws -> Bool {
        try validateName(name)
        let editable = Set(contents.nodes.filter(\.isEditable).map(\.id))
        guard let current = contents.edges.first(where: { $0.id == id }),
            editable.contains(current.fromID), editable.contains(current.toID),
            let edge = model.rootElement()?.elements(forName: "edges").first?.elements(forName: "edge")
                .first(where: { $0.attribute(forName: "id")?.stringValue == id })
        else { throw DocumentError.invalidNode }
        // Bone names are exact template lookup identities; trimming would silently retarget a binding.
        guard !current.hasExactBoneName(name) else { return false }
        write(name, to: edge)
        return true
    }

    static func setMany(model: XMLDocument, contents: DocumentContents, ids: Set<String>, name: String) throws -> Bool {
        try validateName(name)
        guard !ids.isEmpty else { return false }
        let requested = Set(ids.map { Data($0.utf8) })
        let eligible = EdgeBoneAssignmentEligibility.edgeIDs(
            nodes: contents.nodes, edges: contents.edges, parts: contents.parts)
        guard requested.isSubset(of: eligible) else { throw DocumentError.invalidNode }
        let changed = Set(
            contents.edges.filter {
                requested.contains(Data($0.id.utf8)) && !$0.hasExactBoneName(name)
            }.map { Data($0.id.utf8) })
        guard !changed.isEmpty else { return false }
        let elements = model.rootElement()?.elements(forName: "edges").first?.elements(forName: "edge") ?? []
        let selected = elements.filter {
            $0.attribute(forName: "id")?.stringValue.map { changed.contains(Data($0.utf8)) } == true
        }
        // Complete preflight before editing the single owned DOM.
        guard selected.count == changed.count else { throw DocumentError.invalidNode }
        for edge in selected { write(name, to: edge) }
        return true
    }

    static func clearMany(model: XMLDocument, contents: DocumentContents, ids: Set<String>) throws -> Bool {
        let requested = Set(ids.map { Data($0.utf8) })
        let existing = Set(contents.edges.map { Data($0.id.utf8) })
        guard requested.isSubset(of: existing) else { throw DocumentError.invalidNode }
        let changed = Set(
            contents.edges.filter {
                requested.contains(Data($0.id.utf8)) && !$0.boneName.isEmpty
            }.map { Data($0.id.utf8) })
        guard !changed.isEmpty else { return false }
        let elements = model.rootElement()?.elements(forName: "edges").first?.elements(forName: "edge") ?? []
        let selected = elements.filter {
            $0.attribute(forName: "id")?.stringValue.map { changed.contains(Data($0.utf8)) } == true
        }
        guard selected.count == changed.count else { throw DocumentError.invalidNode }
        // Qt's explicit global rig clear includes locked/hidden owners; geometry is untouched.
        for edge in selected { write("", to: edge) }
        return true
    }

    private static func validateName(_ name: String) throws {
        guard name.utf8.count <= 1024,
            name.unicodeScalars.allSatisfy({
                !CharacterSet.controlCharacters.contains($0) && !CharacterSet.newlines.contains($0)
                    && $0.value != 0xFFFE && $0.value != 0xFFFF
            })
        else { throw DocumentError.invalidBoneName }
    }

    private static func write(_ name: String, to edge: XMLElement) {
        edge.removeAttribute(forName: "boneName")
        if !name.isEmpty {
            let attribute = XMLNode(kind: .attribute)
            attribute.name = "boneName"
            attribute.stringValue = name
            edge.addAttribute(attribute)
        }
    }

}
