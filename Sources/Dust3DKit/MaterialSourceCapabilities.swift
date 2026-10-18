import Dust3DDocument
import Foundation

/// Immutable, best-effort source interpretation paired with a particular mesh/archive snapshot.
public enum MaterialSourceCapabilities: Sendable {
    /// Source interpretation has not been supplied; never assume unsupported details are absent.
    case unknown
    /// Source interpretation succeeded independently of pixel decoding or renderer availability.
    case known(hasLegacySurfaceDetails: Bool)
    /// Original parsing/interpretation failure; geometry remains independently usable.
    case unavailable(cause: any Error)

    /// Nonempty legacy surface metadata, or nil when interpretation is unavailable.
    public var hasLegacySurfaceDetails: Bool? {
        if case .known(let value) = self { return value }
        return nil
    }

    /// Original typed cause for callers to surface alongside conservative compatibility warnings.
    public var issue: (any Error)? {
        if case .unavailable(let cause) = self { return cause }
        return nil
    }

    /// Interpret bounded source metadata without changing bytes or making primary geometry depend on success.
    /// - Parameter data: The exact archive bytes used to generate the accompanying mesh.
    /// - Returns: Known metadata or the original interpretation cause; never a fabricated false value.
    /// - Note: Synchronous parsing belongs on a background service; callers check cancellation around it.
    public static func read(data: Data) -> Self {
        do {
            let components = try Dust3DDocument(data: data).components()
            return .known(hasLegacySurfaceDetails: components.contains { $0.hasLegacySurfaceDetails })
        } catch {
            return .unavailable(cause: error)
        }
    }
}
