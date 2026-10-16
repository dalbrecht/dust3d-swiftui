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
        for component in PartSplitting.componentElements(model)
        where component.attribute(forName: "linkDataType")?.stringValue == "partId"
            && selected.contains(component.attribute(forName: "linkData")?.stringValue ?? "")
        {
            if (component.children ?? []).isEmpty {
                component.detach()
            } else {
                // A reference can also own nested geometry or unknown content; retain it as a group.
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
