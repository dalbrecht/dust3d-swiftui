/// Numeric archive compatibility shared by bounded procedural properties.
package enum EngineScalar {
    package static func isValid(_ value: Double, in bounds: ClosedRange<Double>) -> Bool {
        guard value.isFinite, !value.isSubnormal, bounds.contains(value) else { return false }
        let engineValue = Float(value)
        // The generator stores these properties as Float; a nonzero edit must not silently become zero.
        return engineValue.isFinite && (value == 0 || engineValue != 0)
    }

    package static func parse(_ text: String, in bounds: ClosedRange<Double>) -> Double? {
        guard let value = parseNumber(text), isValid(value, in: bounds) else { return nil }
        return value
    }

    /// Validate an authored Double coordinate using the snapshot validator's decimal and prefix rules.
    static func parseArchiveDouble(_ text: String, in bounds: ClosedRange<Double>) -> Double? {
        func isLeadingWhitespace(_ byte: UInt8) -> Bool { byte == 32 || (9...13).contains(byte) }
        guard let last = text.utf8.last, !isLeadingWhitespace(last) else { return nil }
        let number = String(decoding: text.utf8.drop(while: isLeadingWhitespace), as: UTF8.self)
        guard let value = parseNumber(number), !value.isSubnormal, bounds.contains(value) else { return nil }
        return value
    }

    private static func parseNumber(_ text: String) -> Double? {
        // The inherited core accepts both decimal separators for archives from older locales.
        let numericText = String(text.map { $0 == "," ? "." : $0 })
        guard let value = Double(numericText), value.isFinite else { return nil }
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
