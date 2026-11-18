import Dust3DDocument
import Foundation

/// Stored common timing for a type without a declared clip. No dynamic defaults or generator are inferred.
package struct UnknownAnimationTimingDraft {
    private enum Field: String, CaseIterable {
        case durationSeconds, frameCount
    }

    package let defaultSeconds = 3.0
    package let defaultFrames = 90
    package let timing: AnimationTimingDefinition
    private let record: DocumentAnimation
    private var changes: [Field: String?] = [:]

    package static func admits(_ record: DocumentAnimation) -> Bool {
        record.type?.isEmpty == false
            && record.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    package init(record: DocumentAnimation, timing: AnimationTimingDefinition) {
        self.record = record
        self.timing = timing
    }

    package func value(for name: String) -> String? {
        guard let field = Field(rawValue: name) else { return nil }
        return changes[field] ?? record.parameter(named: name)
    }

    package mutating func setText(name: String, value: String?) {
        guard let field = Field(rawValue: name) else { return }
        let original = record.parameter(named: name)
        if original.map({ Data($0.utf8) }) == value.map({ Data($0.utf8) }) {
            changes.removeValue(forKey: field)
        } else {
            changes.updateValue(value, forKey: field)
        }
    }

    package func validatedEdits() throws -> [AnimationEdit] {
        try Field.allCases.compactMap { field in
            guard let change = changes[field] else { return nil }
            if let change {
                guard let number = Double(change) else { throw AnimationCatalogError.invalidValue }
                switch field {
                case .durationSeconds:
                    try timing.validate(seconds: number, frames: Double(timing.minimumFrames))
                case .frameCount:
                    try timing.validate(seconds: timing.minimumSeconds, frames: number)
                }
            }
            return .setParameter(name: field.rawValue, value: change)
        }
    }
}
