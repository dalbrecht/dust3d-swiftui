import Foundation

enum ComponentSmoothing {
    static func degrees(_ element: XMLElement) -> Double? {
        let text = element.attribute(forName: "smoothCutoffDegrees")?.stringValue ?? ""
        if text.isEmpty { return 0 }
        guard let value = Double(text), isValid(value) else { return nil }
        return value
    }

    private static func isValid(_ value: Double) -> Bool {
        value.isFinite && (0...180).contains(value)
    }

    static func set(_ model: XMLDocument, id: String, degrees: Double) throws -> Bool {
        guard isValid(degrees) else { throw DocumentError.invalidComponentSmoothing }
        let components = try ComponentHierarchy.read(model)
        guard let component = components.first(where: { $0.id == id }),
            let element = PartSplitting.componentElements(model).first(where: {
                $0.attribute(forName: "id")?.stringValue == id
            })
        else { throw DocumentError.missingComponent(id) }
        guard component.smoothCutoffDegrees != degrees else { return false }
        element.removeAttribute(forName: "smoothCutoffDegrees")
        // Upstream omits the default zero cutoff when saving; retain every unrelated attribute.
        if degrees > 0 {
            let attribute = XMLNode(kind: .attribute)
            attribute.name = "smoothCutoffDegrees"
            attribute.stringValue = String(degrees)
            element.addAttribute(attribute)
        }
        return true
    }
}
