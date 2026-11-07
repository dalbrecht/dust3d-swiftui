import Foundation

extension ComponentColorImageValue {
    static func read(_ element: XMLElement) -> Self {
        guard let text = element.attribute(forName: "colorImageId")?.stringValue, !text.isEmpty else { return .unset }
        return DocumentTextureImages.identityBytes(text) == nil ? .unsupported(text) : .reference(text)
    }

    static func element(_ model: XMLDocument, id: String) throws -> XMLElement {
        _ = try ComponentHierarchy.read(model)
        guard
            let element = PartSplitting.componentElements(model).first(where: {
                $0.attribute(forName: "id")?.stringValue == id
            })
        else {
            throw DocumentError.missingComponent(id)
        }
        return element
    }

    static func elements(_ model: XMLDocument, ids: [String]) throws -> [XMLElement] {
        guard ids.count <= ComponentHierarchy.maximumCount else { throw DocumentError.limitExceeded }
        guard !ids.isEmpty else { return [] }
        let keys = ids.map { Data($0.utf8) }
        guard Set(keys).count == keys.count else { throw DocumentError.invalidComponentStructure }
        _ = try ComponentHierarchy.read(model)
        let indexed = Dictionary(
            uniqueKeysWithValues: PartSplitting.componentElements(model).compactMap { element in
                element.attribute(forName: "id")?.stringValue.map { (Data($0.utf8), element) }
            })
        return try zip(ids, keys).map { id, key in
            try Task.checkCancellation()
            guard let element = indexed[key] else { throw DocumentError.missingComponent(id) }
            return element
        }
    }

    static func set(_ elements: [XMLElement], imageID: String?) throws -> Bool {
        var changed = false
        for element in elements {
            try Task.checkCancellation()
            if set(element, imageID: imageID) { changed = true }
        }
        return changed
    }

    static func set(_ element: XMLElement, imageID: String?) -> Bool {
        let current = read(element)
        if let imageID, case .reference(let existing) = current,
            DocumentTextureImages.identityBytes(existing) == DocumentTextureImages.identityBytes(imageID)
        {
            return false
        }
        if imageID == nil, current == .unset { return false }
        element.removeAttribute(forName: "colorImageId")
        if let imageID {
            let attribute = XMLNode(kind: .attribute)
            attribute.name = "colorImageId"
            attribute.stringValue = imageID
            element.addAttribute(attribute)
        }
        return true
    }
}
