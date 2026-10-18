import Foundation

/// Pure diagnostic rows keep source provenance separate from the running process identity.
public struct BuildIdentityPresentation: Sendable {
    public struct Row: Identifiable, Sendable {
        public let label: String
        public let value: String
        public var id: String { label }
    }

    public let status: String
    public let failureDescription: String?
    public let rows: [Row]

    /// Select the packaged QA name from captured identity without rereading a mutable bundle.
    /// - Parameters:
    ///   - bundleIdentifier: Bundle identity captured when the process started.
    ///   - fallback: The owning app's name for canonical or unidentified launches.
    /// - Returns: The distinct QA name for its existing identity, otherwise the caller's name.
    public static func applicationName(bundleIdentifier: String?, fallback: String) -> String {
        bundleIdentifier == "org.dust3d.editor.combine-qa" ? "Dust3D Editor QA" : fallback
    }

    /// Present one immutable startup capture without consulting filesystem or application state.
    /// - Parameter identity: The value captured from the loaded executable at startup.
    public init(identity: RuntimeBuildIdentity) {
        var result: [Row] = []
        switch identity.metadata {
        case .success(let metadata):
            status = metadata.summary
            failureDescription = nil
            result = [
                Row(label: "Source revision", value: metadata.sourceRevision),
                Row(label: "Source digest", value: metadata.sourceDigest),
                Row(label: "Core revision", value: metadata.coreRevision),
            ]
        case .failure(let cause):
            status = "Build identity unavailable"
            failureDescription = cause.localizedDescription
        }
        result.append(Row(label: "Launch bundle ID", value: identity.launchBundleIdentifier ?? "Unavailable"))
        result.append(Row(label: "Process ID", value: String(identity.processIdentifier)))
        result.append(Row(label: "Captured at", value: identity.capturedAt.ISO8601Format()))
        rows = result
    }
}
