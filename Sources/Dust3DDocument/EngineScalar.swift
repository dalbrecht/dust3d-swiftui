/// Numeric archive compatibility shared by bounded procedural properties.
package enum EngineScalar {
    package static func isValid(_ value: Double, in bounds: ClosedRange<Double>) -> Bool {
        value.isFinite && !value.isSubnormal && bounds.contains(value)
    }

    package static func parse(_ text: String, in bounds: ClosedRange<Double>) -> Double? {
        guard let value = Double(text), isValid(value, in: bounds) else { return nil }
        if value == 0 {
            // Swift rounds tiny literals to zero; the inherited strtod parser rejects their nonzero significands.
            let normalized = text.lowercased()
            let separator: Character = normalized.contains("0x") ? "p" : "e"
            let significand = normalized.split(separator: separator, maxSplits: 1).first ?? ""
            guard !significand.utf8.contains(where: { (49...57).contains($0) || (97...102).contains($0) }) else {
                return nil
            }
        }
        return value
    }
}
