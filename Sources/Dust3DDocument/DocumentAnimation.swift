import Foundation

/// Retained parameter spelling and value; no numeric parsing or generation is implied.
public struct DocumentAnimationParameter: Sendable, Equatable {
    public let name: String
    public let value: String

    public static func == (lhs: Self, rhs: Self) -> Bool {
        AnimationTextIdentity.matches(lhs.name, rhs.name) && AnimationTextIdentity.matches(lhs.value, rhs.value)
    }
}

/// Stored animation intent in source order, including unsupported types and incomplete metadata.
public struct DocumentAnimation: Sendable, Equatable {
    public let id: String
    public let name: String?
    public let type: String?
    /// Ordered source parameters, preserving byte-distinct names that Swift dictionaries can merge.
    public let parameters: [DocumentAnimationParameter]

    /// Read one exact UTF-8 parameter name, excluding id/name/type metadata.
    /// - Parameter name: Case-sensitive source spelling, without normalization or trimming.
    /// - Returns: Retained text or nil; does not evaluate a clip or validate playback settings.
    /// - Example: `row.parameter(named: "duration")`.
    public func parameter(named name: String) -> String? {
        parameters.first { AnimationTextIdentity.matches($0.name, name) }?.value
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        AnimationTextIdentity.matches(lhs.id, rhs.id) && AnimationTextIdentity.matches(lhs.name, rhs.name)
            && AnimationTextIdentity.matches(lhs.type, rhs.type) && lhs.parameters == rhs.parameters
    }
}

/// Typed metadata errors; archive/XML quotas continue to use DocumentError.
public enum DocumentAnimationError: LocalizedError, Equatable, Sendable {
    case invalidMetadata, invalidIdentity, invalidName, invalidType, invalidParameter
    case missingAnimation(String)
    case duplicateIdentity(String)

    public var errorDescription: String? {
        switch self {
        case .invalidMetadata:
            return "Animation metadata has ambiguous containers, missing identities or unsupported tags."
        case .invalidIdentity: return "Use a nonempty animation identity of at most 1024 UTF-8 bytes without controls."
        case .invalidName: return "Use an animation name of at most 1024 UTF-8 bytes without controls or newlines."
        case .invalidType: return "Use a nonempty animation type of at most 1024 UTF-8 bytes without controls."
        case .invalidParameter:
            return "Use an unqualified parameter name and a value of at most 4096 UTF-8 bytes without controls."
        case .missingAnimation(let id): return "Animation \(id) is not present in this document."
        case .duplicateIdentity(let id): return "Animation identity \(id) is already present in this document."
        }
    }
}

enum AnimationTextIdentity {
    static func matches(_ first: String?, _ second: String?) -> Bool {
        switch (first, second) {
        case (nil, nil): return true
        case (.some(let first), .some(let second)): return first.utf8.elementsEqual(second.utf8)
        default: return false
        }
    }
}
