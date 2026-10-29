/// One finite preset override, distinct from a dynamic widget's nominal default.
public struct AnimationParameterDefault: Sendable {
    public let name: String
    public let value: Double

    /// Admit a copied preset override without evaluating or storing it in a document.
    /// - Parameters: name is an unqualified document parameter key; value is a finite declaration.
    /// - Throws: `AnimationCatalogError.invalidDefinition` for invalid metadata.
    /// - Example: `try AnimationParameterDefault(name: "speed", value: 1)`.
    public init(name: String, value: Double) throws {
        guard AnimationCatalogText.isParameterName(name), value.isFinite else {
            throw AnimationCatalogError.invalidDefinition
        }
        self.name = name
        self.value = value
    }
}

/// Owned fixed-catalog information. Timing and generator names do not imply evaluated playback support.
public struct AnimationClipDefinition: Sendable {
    /// Host metadata collection cap; not a geometry/workspace quota.
    public static let maximumParameterCount = 256
    /// Host metadata collection cap; not a native generator limit.
    public static let maximumControlCount = 256
    public let type: String
    public let rig: String
    public let generator: String
    public let seconds: Double
    public let samples: Int
    public let loops: Bool
    public let isLegacyAlias: Bool
    public let defaults: [AnimationParameterDefault]
    public let controls: [AnimationControlDefinition]

    /// Admit copied clip identity/timing and ordered override/control metadata.
    /// - Parameters:
    ///   - type: Exact bounded inherited type identity, including legacy aliases.
    ///   - rig: Exact bounded declared rig identity.
    ///   - generator: Exact bounded generator identity; no generator is called.
    ///   - seconds: Finite positive declared duration, not a measured/evaluated result.
    ///   - samples: Positive 32-bit declared sample count, without allocating frames.
    ///   - loops: Declared looping intent.
    ///   - isLegacyAlias: Whether the inherited entry is an alias.
    ///   - defaults: Unique bounded preset overrides in source order.
    ///   - controls: Unique bounded widget declarations in source order.
    /// - Throws: `invalidDefinition` for invalid/ambiguous metadata; `limitExceeded` for collection caps.
    /// - Example: `try AnimationClipDefinition(type: "BipedIdle", rig: "Biped", generator: "BipedIdle", seconds: 4, samples: 90, loops: true, isLegacyAlias: false, defaults: [], controls: [])`.
    public init(
        type: String, rig: String, generator: String, seconds: Double, samples: Int,
        loops: Bool, isLegacyAlias: Bool, defaults: [AnimationParameterDefault], controls: [AnimationControlDefinition]
    ) throws {
        try AnimationCatalogAdmission.validateCount(defaults.count, maximum: Self.maximumParameterCount)
        try AnimationCatalogAdmission.validateCount(controls.count, maximum: Self.maximumControlCount)
        guard AnimationCatalogText.isIdentity(type), AnimationCatalogText.isIdentity(rig),
            AnimationCatalogText.isIdentity(generator), seconds.isFinite, seconds > 0,
            samples > 0, Int32(exactly: samples) != nil
        else { throw AnimationCatalogError.invalidDefinition }
        try AnimationCatalogAdmission.validateUnique(defaults.map(\.name))
        try AnimationCatalogAdmission.validateUnique(controls.map(\.name))
        self.type = type
        self.rig = rig
        self.generator = generator
        self.seconds = seconds
        self.samples = samples
        self.loops = loops
        self.isLegacyAlias = isLegacyAlias
        self.defaults = defaults
        self.controls = controls
    }
}

/// Common reference-widget declarations, separate from native generation/sampling acceptance.
public struct AnimationTimingDefinition: Sendable {
    public let minimumSeconds: Double
    public let maximumSeconds: Double
    public let decimalPlaces: Int
    public let secondsStep: Double
    public let minimumFrames: Int
    public let maximumFrames: Int
    public let framesStep: Int

    /// Admit copied common-widget metadata without rounding or rewriting stored document values.
    /// - Parameters: duration bounds/step must be finite positive; decimals are 0...12;
    ///   frame bounds/step must be positive 32-bit integers with ordered bounds.
    /// - Throws: `AnimationCatalogError.invalidDefinition` for inconsistent metadata.
    /// - Example: `try AnimationTimingDefinition(minimumSeconds: 0.01, maximumSeconds: 59.99, decimalPlaces: 2, secondsStep: 0.1, minimumFrames: 1, maximumFrames: 4999, framesStep: 5)`.
    public init(
        minimumSeconds: Double, maximumSeconds: Double, decimalPlaces: Int, secondsStep: Double,
        minimumFrames: Int, maximumFrames: Int, framesStep: Int
    ) throws {
        guard minimumSeconds.isFinite, maximumSeconds.isFinite, secondsStep.isFinite,
            minimumSeconds > 0, minimumSeconds <= maximumSeconds, secondsStep > 0,
            (0...12).contains(decimalPlaces), minimumFrames > 0, minimumFrames <= maximumFrames,
            Int32(exactly: maximumFrames) != nil, framesStep > 0, Int32(exactly: framesStep) != nil
        else { throw AnimationCatalogError.invalidDefinition }
        self.minimumSeconds = minimumSeconds
        self.maximumSeconds = maximumSeconds
        self.decimalPlaces = decimalPlaces
        self.secondsStep = secondsStep
        self.minimumFrames = minimumFrames
        self.maximumFrames = maximumFrames
        self.framesStep = framesStep
    }

    /// Validate an explicit metadata edit without rounding duration or claiming a working sampling grid.
    /// - Parameters: seconds and frames are the user's parsed finite values; frames must be integral.
    /// - Throws: `invalidValue` outside declared bounds/nonfinite; `unrepresentableValue` for fractional frames.
    /// - Example: `try timing.validate(seconds: 1.125, frames: 2)`.
    public func validate(seconds: Double, frames: Double) throws {
        guard seconds.isFinite, frames.isFinite, (minimumSeconds...maximumSeconds).contains(seconds),
            (Double(minimumFrames)...Double(maximumFrames)).contains(frames)
        else { throw AnimationCatalogError.invalidValue }
        guard Int32(exactly: frames) != nil else { throw AnimationCatalogError.unrepresentableValue }
    }
}

/// Pure owned edit capabilities consumed by the host UI; never retains C pointers, archives or evaluated frames.
public struct AnimationAuthoringCatalog: Sendable {
    /// Host collection admission cap, independent of engine algorithm limits.
    public static let maximumClipCount = 2048
    /// Host collection admission cap, preserving the reference's surface order.
    public static let maximumSurfaceCount = 128
    public let clips: [AnimationClipDefinition]
    public let surfaceMaterials: [String]
    public let timing: AnimationTimingDefinition

    /// Admit bounded, unambiguous copied catalog collections without canonicalizing identities.
    /// - Parameters: clips and surfaces retain their supplied order; timing declares common widget limits.
    /// - Throws: `invalidDefinition` for ambiguous/invalid names; `limitExceeded` for collection caps.
    /// - Example: `try AnimationAuthoringCatalog(clips: clips, surfaceMaterials: surfaces, timing: timing)`.
    public init(
        clips: [AnimationClipDefinition], surfaceMaterials: [String], timing: AnimationTimingDefinition
    ) throws {
        try AnimationCatalogAdmission.validateCount(clips.count, maximum: Self.maximumClipCount)
        try AnimationCatalogAdmission.validateCount(surfaceMaterials.count, maximum: Self.maximumSurfaceCount)
        guard surfaceMaterials.allSatisfy({ AnimationCatalogText.isIdentity($0) }) else {
            throw AnimationCatalogError.invalidDefinition
        }
        try AnimationCatalogAdmission.validateUnique(clips.map(\.type))
        try AnimationCatalogAdmission.validateUnique(surfaceMaterials)
        self.clips = clips
        self.surfaceMaterials = surfaceMaterials
        self.timing = timing
    }

    /// Find an exact source identity, without Swift canonical-equivalence substitution.
    /// - Parameter type: Exact retained type spelling, including unsupported names.
    /// - Returns: Declared clip or nil; unknown intent is never rewritten.
    /// - Example: `catalog.clip(type: record.type ?? "")`.
    public func clip(type: String) -> AnimationClipDefinition? {
        clips.first { $0.type.utf8.elementsEqual(type.utf8) }
    }
}

enum AnimationCatalogAdmission {
    static func validateCount(_ count: Int, maximum: Int) throws {
        guard (0...maximum).contains(count) else { throw AnimationCatalogError.limitExceeded }
    }

    static func validateUnique(_ names: [String]) throws {
        var seen = Set<[UInt8]>()
        for name in names {
            guard seen.insert(Array(name.utf8)).inserted else { throw AnimationCatalogError.invalidDefinition }
        }
    }
}
