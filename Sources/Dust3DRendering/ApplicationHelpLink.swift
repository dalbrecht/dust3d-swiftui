import AppKit
import Foundation

/// Shared project destinations for explicit Help-menu actions in both native apps.
public enum ApplicationHelpLink: CaseIterable, Hashable, Sendable {
    case nativeProject
    case reportIssue
    case upstreamWebsite

    /// Human-readable menu title; the upstream project is distinct from the native issue tracker.
    public var title: String {
        switch self {
        case .nativeProject: "Project on GitHub"
        case .reportIssue: "Report an Issue"
        case .upstreamWebsite: "Upstream Dust3D Website"
        }
    }

    private var address: String {
        switch self {
        case .nativeProject: "https://github.com/dalbrecht/dust3d-swiftui"
        case .reportIssue: "https://github.com/dalbrecht/dust3d-swiftui/issues/new"
        case .upstreamWebsite: "https://dust3d.org/"
        }
    }

    /// Ask macOS to open the selected website, presenting any refusal through its standard error UI.
    /// Call only in response to an explicit user command; constructing menus performs no navigation.
    @MainActor public func open() {
        open(using: { NSWorkspace.shared.open($0) }, report: { NSApplication.shared.presentError($0) })
    }

    @MainActor func open(using opener: (URL) -> Bool, report: (ApplicationHelpLinkError) -> Void) {
        if let error = Self.failure(address: address, using: opener) { report(error) }
    }

    @MainActor static func failure(address: String, using opener: (URL) -> Bool) -> ApplicationHelpLinkError? {
        guard let url = URL(string: address), url.scheme == "https", url.host?.isEmpty == false else {
            return .invalidDestination(address)
        }
        return opener(url) ? nil : .openDeclined(url.absoluteString)
    }
}

/// NSWorkspace supplies only an accepted/declined result; keep that result and its destination explicit.
enum ApplicationHelpLinkError: LocalizedError, Equatable {
    case invalidDestination(String)
    case openDeclined(String)

    var errorDescription: String? {
        switch self {
        case .invalidDestination(let address): "The help link is invalid: \(address)"
        case .openDeclined(let address): "macOS declined to open the help link: \(address)"
        }
    }
}
