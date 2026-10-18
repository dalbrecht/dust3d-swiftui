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
