import Dust3DDocument
import Foundation

/// Common stored parameters for a type without a declared clip.
package struct UnknownAnimationParameterDraft {
    private enum Field: String, CaseIterable {
        case durationSeconds, frameCount, surfaceMaterial
    }

    package let defaultSeconds = 3.0
    package let defaultFrames = 90
    package let timing: AnimationTimingDefinition
    package let surfaceMaterials: [String]
    private let record: DocumentAnimation
    private var changes: [Field: String?] = [:]

    package static func admits(_ record: DocumentAnimation) -> Bool {
        record.type?.isEmpty == false
            && record.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    package init(record: DocumentAnimation, catalog: AnimationAuthoringCatalog) {
        self.record = record
        timing = catalog.timing
        surfaceMaterials = catalog.surfaceMaterials
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

    package mutating func stepTiming(name: String, increasing: Bool) {
        let fallback = name == "durationSeconds" ? defaultSeconds : Double(defaultFrames)
        guard
            let next = AnimationParameterDraft.steppedTimingText(
                name: name, current: value(for: name), fallback: fallback, timing: timing, increasing: increasing)
        else { return }
        setText(
            name: name,
            value: AnimationParameterDraft.timingStepOverride(
                next, original: record.parameter(named: name), fallback: fallback))
    }

    package func validatedEdits() throws -> [AnimationEdit] {
        try Field.allCases.compactMap { field in
            guard let change = changes[field] else { return nil }
            if let change {
                switch field {
                case .durationSeconds:
                    guard let number = Double(change) else { throw AnimationCatalogError.invalidValue }
                    try timing.validate(seconds: number, frames: Double(timing.minimumFrames))
                case .frameCount:
                    guard let number = Double(change) else { throw AnimationCatalogError.invalidValue }
                    try timing.validate(seconds: timing.minimumSeconds, frames: number)
                case .surfaceMaterial:
                    guard surfaceMaterials.contains(where: { $0.utf8.elementsEqual(change.utf8) }) else {
                        throw AnimationCatalogError.invalidValue
                    }
                }
            }
            return .setParameter(name: field.rawValue, value: change)
        }
    }
}
