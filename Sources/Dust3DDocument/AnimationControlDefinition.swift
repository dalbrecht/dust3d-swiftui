import Foundation

/// Invalid catalog declarations are distinct from explicit stored-value projection failures.
public enum AnimationCatalogError: LocalizedError, Equatable, Sendable {
    case invalidDefinition, invalidValue, unrepresentableValue

    public var errorDescription: String? {
        switch self {
        case .invalidDefinition: "The animation catalog contains an invalid control definition."
        case .invalidValue: "Choose a finite animation parameter value within the declared control range."
        case .unrepresentableValue: "The animation parameter exceeds the control's integer representation."
        }
    }
}

/// Immutable inherited widget declaration, without native ownership or animation evaluation.
/// Nominal defaults and discrete slider values are deliberately different concepts.
public struct AnimationControlDefinition: Sendable, Equatable {
    public let name: String
    public let label: String
    public let minimumSlider: Int
    public let maximumSlider: Int
    public let defaultSlider: Int
    public let defaultParameter: Double
    public let divisor: Double
    public let multiplier: Double

    /// Admit one copied metadata control before it can become editable presentation.
    /// - Parameters:
    ///   - name: Bounded unqualified document parameter key.
    ///   - label: Bounded nonempty display name, retaining exact UTF-8 spelling.
    ///   - minimumSlider: Inclusive inherited 32-bit slider lower bound.
    ///   - maximumSlider: Inclusive inherited 32-bit slider upper bound.
    ///   - defaultSlider: Declared widget default, matching the nominal default's projection.
    ///   - defaultParameter: Finite nominal parameter default; never substituted for stored intent.
    ///   - divisor: Finite positive slider divisor from the canonical catalog.
    ///   - multiplier: Finite positive parameter multiplier from the canonical catalog.
    /// - Throws: `AnimationCatalogError.invalidDefinition` for inadmissible metadata.
    /// - Example: `try AnimationControlDefinition(name: "speed", label: "Speed", minimumSlider: 0, maximumSlider: 200, defaultSlider: 100, defaultParameter: 1, divisor: 100, multiplier: 1)`.
    public init(
        name: String, label: String, minimumSlider: Int, maximumSlider: Int,
        defaultSlider: Int, defaultParameter: Double, divisor: Double, multiplier: Double
    ) throws {
        guard AnimationCatalogText.isParameterName(name), AnimationCatalogText.isIdentity(label),
            Int32(exactly: minimumSlider) != nil, Int32(exactly: maximumSlider) != nil,
            minimumSlider <= maximumSlider, (minimumSlider...maximumSlider).contains(defaultSlider),
            defaultParameter.isFinite, divisor.isFinite, divisor > 0, multiplier.isFinite, multiplier > 0,
            (Double(minimumSlider) / divisor * multiplier).isFinite,
            (Double(maximumSlider) / divisor * multiplier).isFinite
        else { throw AnimationCatalogError.invalidDefinition }
        self.name = name
        self.label = label
        self.minimumSlider = minimumSlider
        self.maximumSlider = maximumSlider
        self.defaultSlider = defaultSlider
        self.defaultParameter = defaultParameter
        self.divisor = divisor
        self.multiplier = multiplier
        guard projectedSlider(for: defaultParameter) == defaultSlider else {
            throw AnimationCatalogError.invalidDefinition
        }
    }

    /// Project an explicit slider edit with the catalog's declared operation order.
    /// - Parameter slider: Inclusive declared integer range.
    /// - Returns: Finite `slider / divisor * multiplier`, without generation or document mutation.
    /// - Throws: `AnimationCatalogError.invalidValue` for a slider outside its declared range.
    /// - Example: `try control.value(at: control.defaultSlider)`.
    public func value(at slider: Int) throws -> Double {
        guard (minimumSlider...maximumSlider).contains(slider) else { throw AnimationCatalogError.invalidValue }
        return Double(slider) / divisor * multiplier
    }

    /// Project a display position without rewriting the retained stored parameter.
    /// - Parameter value: Finite retained/explicit value, including values outside nominal widget bounds.
    /// - Returns: Truncation toward zero followed by widget bounds, matching inherited control semantics.
    /// - Throws: `invalidValue` for nonfinite values; `unrepresentableValue` before any unsafe integer cast.
    /// - Example: `try control.slider(for: control.defaultParameter)`.
    public func slider(for value: Double) throws -> Int {
        guard value.isFinite else { throw AnimationCatalogError.invalidValue }
        guard let result = projectedSlider(for: value) else { throw AnimationCatalogError.unrepresentableValue }
        return result
    }

    private func projectedSlider(for value: Double) -> Int? {
        let scaled = value / multiplier * divisor
        guard scaled.isFinite, let integer = Int32(exactly: scaled.rounded(.towardZero)) else { return nil }
        return min(max(Int(integer), minimumSlider), maximumSlider)
    }
}

enum AnimationCatalogText {
    static func isIdentity(_ value: String, maximum: Int = 1024) -> Bool {
        !value.isEmpty && value.utf8.count <= maximum
            && value.unicodeScalars.allSatisfy {
                !CharacterSet.controlCharacters.contains($0) && !CharacterSet.newlines.contains($0)
                    && $0.value != 0xFFFE && $0.value != 0xFFFF
            }
    }

    static func isParameterName(_ value: String) -> Bool {
        let bytes = value.utf8
        func letter(_ byte: UInt8) -> Bool { (65...90).contains(byte) || (97...122).contains(byte) || byte == 95 }
        guard let first = bytes.first, letter(first), bytes.count <= 128,
            !["id", "name", "type", "xmlns"].contains(value)
        else { return false }
        return bytes.allSatisfy { letter($0) || (48...57).contains($0) || $0 == 45 || $0 == 46 }
    }
}
