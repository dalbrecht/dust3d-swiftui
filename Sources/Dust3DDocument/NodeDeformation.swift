import Foundation

/// Per-node taper uses the part scale attribute names with positive native scalar bounds.
package struct NodeDeformation: Equatable, Sendable {
    private static let bounds = 0.0...1_000_000.0
    private let width: Double?
    private let thickness: Double?

    init(_ element: XMLElement) {
        width = Self.read(.width, from: element)
        thickness = Self.read(.thickness, from: element)
    }

    func scale(_ property: PartDeformationProperty) -> Double? {
        switch property {
        case .width: width
        case .thickness: thickness
        }
    }

    package static func parse(_ text: String) -> Double? {
        guard let value = EngineScalar.parse(text, in: bounds), value > 0 else { return nil }
        return value
    }

    static func isValid(_ value: Double) -> Bool {
        value > 0 && EngineScalar.isValid(value, in: bounds)
    }

    private static func read(_ property: PartDeformationProperty, from element: XMLElement) -> Double? {
        guard let attribute = element.attribute(forName: property.rawValue) else { return 1 }
        return parse(attribute.stringValue ?? "")
    }

    static func write(_ property: PartDeformationProperty, value: Double, on element: XMLElement) {
        let key = property.rawValue
        if value == 1 {
            element.removeAttribute(forName: key)
        } else if let attribute = element.attribute(forName: key) {
            attribute.stringValue = String(value)
        } else {
            let attribute = XMLNode(kind: .attribute)
            attribute.name = key
            attribute.stringValue = String(value)
            element.addAttribute(attribute)
        }
    }
}
