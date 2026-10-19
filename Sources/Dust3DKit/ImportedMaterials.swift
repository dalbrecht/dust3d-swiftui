import Foundation

/// Transferred glTF alpha policy; it does not imply renderer support.
public enum ImportedAlphaMode: Sendable, Equatable { case opaque, mask, blend }

/// Declared encoded format. Successful pixel decoding is a separate operation.
public enum ImportedImageEncoding: String, Sendable, Equatable {
    case png = "image/png"
    case jpeg = "image/jpeg"
}

/// Explicit magnification filters; nil in a sampler preserves unspecified filtering.
public enum ImportedMagnificationFilter: UInt32, Sendable, Equatable, CaseIterable {
    case nearest = 9728
    case linear = 9729
}

/// Explicit minification filters, preserving the original mipmap selection.
public enum ImportedMinificationFilter: UInt32, Sendable, Equatable, CaseIterable {
    case nearest = 9728
    case linear = 9729
    case nearestMipmapNearest = 9984
    case linearMipmapNearest = 9985
    case nearestMipmapLinear = 9986
    case linearMipmapLinear = 9987
}

/// Wrapping modes retained independently on the two texture axes.
public enum ImportedTextureWrapMode: UInt32, Sendable, Equatable, CaseIterable {
    case repeatTexture = 10497
    case clampToEdge = 33071
    case mirroredRepeat = 33648
}

/// Immutable sampler state; optional filter fields retain source absence.
public struct ImportedTextureSampler: Sendable, Equatable {
    public let magnification: ImportedMagnificationFilter?
    public let minification: ImportedMinificationFilter?
    public let wrapS: ImportedTextureWrapMode
    public let wrapT: ImportedTextureWrapMode
}

/// Independent encoded storage. Neither the declaration nor these bytes are validated pixels.
public struct ImportedEncodedImage: Sendable, Equatable {
    public let encoding: ImportedImageEncoding
    public let bytes: Data
}

/// Copied model-level material facts. Instance policy remains in the original document.
public struct ImportedModelMaterial: Sendable, Equatable {
    public let id: String
    public let baseColor: SIMD4<Double>
    public let metallic: Double
    public let roughness: Double
    public let emissive: SIMD3<Double>
    public let alphaMode: ImportedAlphaMode
    public let alphaCutoff: Double
    public let isDoubleSided: Bool
    public let sampler: ImportedTextureSampler?
    public let image: ImportedEncodedImage?
}

/// Original identities; nil component identifies an uninstanced imported part.
public struct ImportedMaterialBinding: Sendable, Equatable {
    public let componentID: String?
    public let partID: String
    public let modelID: String

    /// Compare opaque UTF-8 identities without Unicode or UUID normalization.
    /// - Parameters:
    ///   - lhs: First original binding.
    ///   - rhs: Second original binding.
    /// - Returns: True only when identity bytes and optional presence match.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.partID.utf8.elementsEqual(rhs.partID.utf8), lhs.modelID.utf8.elementsEqual(rhs.modelID.utf8) else {
            return false
        }
        switch (lhs.componentID, rhs.componentID) {
        case (nil, nil): return true
        case (.some(let first), .some(let second)): return first.utf8.elementsEqual(second.utf8)
        default: return false
        }
    }
}

/// Immutable copies usable after native owner destruction and across actor boundaries.
public struct ImportedMaterials: Sendable, Equatable {
    public let models: [ImportedModelMaterial]
    public let bindings: [ImportedMaterialBinding]
    public let nativePayloadBytes: Int
    /// Record capacities plus copied UTF-8 and byte lengths, excluding allocator/workspace overhead.
    public let copiedPayloadBytes: Int
}

/// Independent native and Swift output budgets; input/decoder limits apply separately.
public struct ImportedMaterialOptions: Sendable {
    public let maximumNativePayloadBytes: Int
    public let maximumCopiedPayloadBytes: Int

    /// Configure logical ownership budgets, validated before loading.
    /// - Parameters:
    ///   - maximumNativePayloadBytes: Zero selects the core's 64 MiB default; maximum 256 MiB.
    ///   - maximumCopiedPayloadBytes: Positive Swift-copy budget up to 256 MiB, default 64 MiB.
    /// - Note: Excludes input/decoder workspace, temporary indexes and allocator capacity.
    public init(maximumNativePayloadBytes: Int = 0, maximumCopiedPayloadBytes: Int = 64 * 1024 * 1024) {
        self.maximumNativePayloadBytes = maximumNativePayloadBytes
        self.maximumCopiedPayloadBytes = maximumCopiedPayloadBytes
    }
}

/// Swift boundary failures remain distinct from original native status/diagnostics.
public enum ImportedMaterialError: LocalizedError, Equatable, Sendable, CaseIterable {
    case invalidLimits, archiveLimitExceeded, copyLimitExceeded, invalidNativeCounts
    case invalidIdentity, invalidMaterial, invalidSampler, invalidImage, invalidBinding

    public var errorDescription: String? {
        switch self {
        case .invalidLimits: return "The imported-material limits are invalid."
        case .archiveLimitExceeded: return "The imported-material archive exceeds 256 MiB."
        case .copyLimitExceeded: return "Copied imported materials exceed the configured output limit."
        case .invalidNativeCounts: return "The engine returned inconsistent imported-material counts."
        case .invalidIdentity: return "The engine returned an invalid imported-material identity."
        case .invalidMaterial: return "The engine returned invalid imported-material factors or flags."
        case .invalidSampler: return "The engine returned an invalid imported texture sampler."
        case .invalidImage: return "The engine returned incomplete imported image metadata."
        case .invalidBinding: return "The engine returned inconsistent imported-material bindings."
        }
    }
}
