import Dust3DDocument
import Foundation

/// Plans model-sidecar names before any animation evaluation or filesystem publication.
package struct CombinedAnimationExportPlan: Sendable {
    package enum Failure: Error, Equatable {
        case outputLimit, duplicateAnimation, duplicateSurface
    }

    package struct Output: Sendable {
        package let animation: DocumentAnimation
        package let surface: String
        package let filename: String
    }

    package let outputs: [Output]

    /// Preserve the supplied document and catalog order. The renderer may later omit silent outputs.
    package init(
        modelName: String, animations: [DocumentAnimation], surfaces: [String], maximumOutputs: Int = 8192
    ) throws {
        let limit = min(maximumOutputs, 8192)
        guard limit >= 0, surfaces.isEmpty || animations.count <= limit / surfaces.count else {
            throw Failure.outputLimit
        }
        guard !animations.isEmpty, !surfaces.isEmpty else {
            outputs = []
            return
        }
        guard Set(animations.map { Data($0.id.utf8) }).count == animations.count else {
            throw Failure.duplicateAnimation
        }
        guard Set(surfaces.map { Data($0.utf8) }).count == surfaces.count else {
            throw Failure.duplicateSurface
        }

        let model = Self.component(modelName, fallback: "Model", maximumBytes: 95)
        let surfaceNames = surfaces.map { Self.component($0, fallback: "Surface", maximumBytes: 40) }
        var claimed: Set<String> = []
        var nextSuffix: [String: Int] = [:]
        var planned: [Output] = []
        planned.reserveCapacity(animations.count * surfaces.count)
        for animation in animations {
            let title = Self.component(animation.name ?? "", fallback: "Animation", maximumBytes: 95)
            for (surface, name) in zip(surfaces, surfaceNames) {
                let stem = "\(model)_\(title)_\(name)"
                let key = Self.collisionKey(stem)
                var candidate = stem
                var suffix = nextSuffix[key, default: 2]
                while !claimed.insert(Self.collisionKey(candidate)).inserted {
                    candidate = "\(stem)_\(suffix)"
                    suffix += 1
                }
                nextSuffix[key] = suffix
                planned.append(Output(animation: animation, surface: surface, filename: candidate + ".wav"))
            }
        }
        outputs = planned
    }

    private static func component(_ value: String, fallback: String, maximumBytes: Int) -> String {
        let separators = CharacterSet(charactersIn: "/:\\").union(.controlCharacters)
        var sanitized = ""
        var count = 0
        for scalar in value.precomposedStringWithCanonicalMapping.unicodeScalars {
            let safe = separators.contains(scalar) ? Unicode.Scalar("_") : scalar
            let size = safe.utf8.count
            guard count + size <= maximumBytes else { break }
            sanitized.unicodeScalars.append(safe)
            count += size
        }
        let trimmed = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: ".").union(.whitespacesAndNewlines))
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func collisionKey(_ stem: String) -> String {
        stem.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .precomposedStringWithCanonicalMapping
    }
}
