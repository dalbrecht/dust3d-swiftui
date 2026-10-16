import Foundation

/// Remove explicitly emptied graph owners without globally collecting legacy/template metadata or assets.
enum EmptyPartCleanup {
    static func apply(_ ids: [String], model: XMLDocument, contents: DocumentContents) throws {
        let selected = Set(ids)
        let partsByID = Dictionary(uniqueKeysWithValues: contents.parts.map { ($0.id, $0) })
        let occupied = Set(contents.nodes.compactMap(\.partID))
        guard selected.count == ids.count,
            ids.allSatisfy({ partsByID[$0]?.isEditable == true && !occupied.contains($0) })
        else { throw DocumentError.invalidNode }
        let parts = model.rootElement()?.elements(forName: "parts").first?.elements(forName: "part") ?? []
        let profileIDs = CutFaceLinks.index(ids)
        for part in parts where selected.contains(part.attribute(forName: "id")?.stringValue ?? "") {
            part.detach()
        }
        // XML formatting whitespace excludes meaningful Unicode spaces in preserved metadata.
        let formattingWhitespace = CharacterSet(charactersIn: " \t\r\n")
        // Classify owners after their descendants, so removed child references cannot leave phantom groups.
        for component in PartSplitting.componentElements(model).reversed()
        where component.attribute(forName: "linkDataType")?.stringValue == "partId"
            && selected.contains(component.attribute(forName: "linkData")?.stringValue ?? "")
        {
            let hasMeaningfulChildren = (component.children ?? []).contains {
                $0.kind != .text || $0.stringValue?.trimmingCharacters(in: formattingWhitespace).isEmpty == false
            }
            if !hasMeaningfulChildren {
                component.detach()
            } else {
                // A reference can own nested geometry or meaningful unknown content; retain it as a group.
                component.removeAttribute(forName: "linkData")
                component.removeAttribute(forName: "linkDataType")
            }
        }
        let nodes = model.rootElement()?.elements(forName: "nodes").first?.elements(forName: "node") ?? []
        for element in parts + nodes
        where CutFaceLinks.target(element.attribute(forName: "cutFace")?.stringValue, in: profileIDs) != nil {
            // A deleted profile cannot supply geometry; removing its known link restores default/inherited shape.
            element.removeAttribute(forName: "cutFace")
        }
    }
}
