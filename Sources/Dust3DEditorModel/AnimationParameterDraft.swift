import Dust3DDocument

/// Pure parameter intent for one fixed stored type; source ownership is enforced by AnimationEditTarget.
/// Unchanged unsupported values never become edits or block a different explicit repair.
public struct AnimationParameterDraft: Sendable {
    public let clip: AnimationClipDefinition
    public let timing: AnimationTimingDefinition
    public let surfaceMaterials: [String]
    private let source: DocumentAnimation
    private struct Entry: Sendable {
        let name: String
        let value: String?
    }
    private var pending: [Entry] = []

    /// Capture exact raw parameters without parsing or normalizing the retained document.
    /// - Parameters: record is the accepted source row; catalog declares the fixed type's controls.
    /// - Throws: `AnimationCatalogError.invalidDefinition` for an unknown/unset type.
    /// - Example: `try AnimationParameterDraft(record: row.source, catalog: catalog)`.
    public init(record: DocumentAnimation, catalog: AnimationAuthoringCatalog) throws {
        guard let type = record.type, let clip = catalog.clip(type: type) else {
            throw AnimationCatalogError.invalidDefinition
        }
        source = record
        self.clip = clip
        timing = catalog.timing
        surfaceMaterials = catalog.surfaceMaterials
    }

    /// Read pending or exact retained text; nil means no stored override, not a normalized number.
    /// - Parameter name: Exact parameter key.
    /// - Returns: Owned raw text, including unsupported/empty values, or nil.
    /// - Example: `draft.value(for: "durationSeconds")`.
    public func value(for name: String) -> String? {
        if let entry = pending.first(where: { Self.matches($0.name, name) }) { return entry.value }
        return source.parameter(named: name)
    }

    /// Record explicit text, retaining intermediate invalid input until validation/repair.
    /// - Parameters: name is a parameter key; value is exact text, or nil to remove an override.
    ///   Restoring the source spelling removes that pending edit, including unsupported source text.
    /// - Example: `draft.setText(name: "durationSeconds", value: "1.125")`.
    public mutating func setText(name: String, value: String?) {
        let index = pending.firstIndex { Self.matches($0.name, name) }
        if Self.matches(source.parameter(named: name), value) {
            if let index { pending.remove(at: index) }
        } else {
            let entry = Entry(name: name, value: value)
            if let index { pending[index] = entry } else { pending.append(entry) }
        }
    }

    /// Make an explicit discrete widget edit, restoring original spelling on an exact numeric round trip.
    /// - Parameters: name identifies a declared dynamic control; index is its inclusive slider value.
    /// - Throws: Original `AnimationCatalogError` before mutation for unknown/out-of-range controls.
    /// - Example: `try draft.setSlider(name: "speed", index: 100)`.
    public mutating func setSlider(name: String, index: Int) throws {
        guard let control = clip.controls.first(where: { Self.matches($0.name, name) }) else {
            throw AnimationCatalogError.invalidValue
        }
        let number = try control.value(at: index)
        let original = source.parameter(named: name)
        if let original, Double(original) == number {
            setText(name: name, value: original)
        } else if original == nil, number == control.defaultParameter {
            setText(name: name, value: nil)
        } else {
            setText(name: name, value: String(number))
        }
    }

    /// Explicitly remove an override; unsupported retained fields are otherwise untouched.
    /// - Parameter name: Known parameter whose inherited default should be used after publication.
    /// - Example: `draft.useDefault(name: "durationSeconds")`.
    public mutating func useDefault(name: String) { setText(name: name, value: nil) }

    /// Validate changed fields only and produce one ordered transaction's commands.
    /// - Returns: Parameter edits without unrelated/untouched values; empty means exact no-op.
    /// - Throws: Original typed catalog validation cause. No document is modified.
    /// - Example: `try await session.editAnimation(draft.validatedEdits(), target: target)`.
    public func validatedEdits() throws -> [AnimationEdit] {
        try pending.map { entry in
            try validate(entry)
            return .setParameter(name: entry.name, value: entry.value)
        }
    }

    private func validate(_ entry: Entry) throws {
        switch entry.name {
        case "durationSeconds":
            if let text = entry.value {
                guard let number = Double(text) else { throw AnimationCatalogError.invalidValue }
                try timing.validate(seconds: number, frames: Double(timing.minimumFrames))
            }
        case "frameCount":
            if let text = entry.value {
                guard let number = Double(text) else { throw AnimationCatalogError.invalidValue }
                try timing.validate(seconds: timing.minimumSeconds, frames: number)
            }
        case "surfaceMaterial":
            if let text = entry.value, !surfaceMaterials.contains(where: { Self.matches($0, text) }) {
                throw AnimationCatalogError.invalidValue
            }
        default:
            guard let control = clip.controls.first(where: { Self.matches($0.name, entry.name) }) else {
                throw AnimationCatalogError.invalidValue
            }
            if let text = entry.value {
                guard let number = Double(text) else { throw AnimationCatalogError.invalidValue }
                _ = try control.slider(for: number)
            }
        }
    }

    /// Seed one new record with displayed widget values, common timing, preset-only overrides and a known surface.
    /// - Parameters: clip is the selected declaration; catalog supplies timing limits and ordered surfaces.
    /// - Returns: Unique ordered parameters for one atomic creation, without generating frames.
    /// - Throws: Original metadata/timing/control cause before publication.
    /// - Example: `try AnimationParameterDraft.initialParameters(for: clip, in: catalog)`.
    public static func initialParameters(
        for clip: AnimationClipDefinition, in catalog: AnimationAuthoringCatalog
    ) throws -> [DocumentAnimationParameter] {
        try catalog.timing.validate(seconds: clip.seconds, frames: Double(clip.samples))
        var values = clip.defaults.map { DocumentAnimationParameter(name: $0.name, value: String($0.value)) }
        func set(_ name: String, _ value: String) {
            let entry = DocumentAnimationParameter(name: name, value: value)
            if let index = values.firstIndex(where: { matches($0.name, name) }) {
                values[index] = entry
            } else {
                values.append(entry)
            }
        }
        set("durationSeconds", String(clip.seconds))
        set("frameCount", String(clip.samples))
        for control in clip.controls { set(control.name, String(try control.value(at: control.defaultSlider))) }
        if let first = catalog.surfaceMaterials.first { set("surfaceMaterial", first) }
        return values
    }

    private static func matches(_ first: String?, _ second: String?) -> Bool {
        switch (first, second) {
        case (nil, nil): true
        case (.some(let first), .some(let second)): first.utf8.elementsEqual(second.utf8)
        default: false
        }
    }
}
