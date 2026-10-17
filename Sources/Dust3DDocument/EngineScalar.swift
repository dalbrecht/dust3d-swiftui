/// Numeric archive compatibility shared by bounded procedural properties.
package enum EngineScalar {
    package static func isValid(_ value: Double, in bounds: ClosedRange<Double>) -> Bool {
        guard value.isFinite, !value.isSubnormal, bounds.contains(value) else { return false }
        let engineValue = Float(value)
        // The generator stores these properties as Float; a nonzero edit must not silently become zero.
        return engineValue.isFinite && (value == 0 || engineValue != 0)
    }

    package static func parse(_ text: String, in bounds: ClosedRange<Double>) -> Double? {
        // The inherited core accepts both decimal separators for archives from older locales.
        let numericText = String(text.map { $0 == "," ? "." : $0 })
        guard let value = Double(numericText), isValid(value, in: bounds) else { return nil }
        if value == 0 {
            // Swift rounds tiny literals to zero; the inherited strtod parser rejects their nonzero significands.
            let normalized = numericText.lowercased()
            let separator: Character = normalized.contains("0x") ? "p" : "e"
            let significand = normalized.split(separator: separator, maxSplits: 1).first ?? ""
            guard !significand.utf8.contains(where: { (49...57).contains($0) || (97...102).contains($0) }) else {
                return nil
            }
        }
        return value
    }
}
