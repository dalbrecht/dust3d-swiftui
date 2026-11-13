import AppKit
import Foundation

/// Shared destinations for explicit Help-menu actions in both native apps.
public enum ApplicationHelpLink: CaseIterable, Hashable, Sendable {
    case nativeProject
    case reportIssue
    case upstreamWebsite
    case upstreamAcknowledgements
    case upstreamSupport

    /// Human-readable menu title; the upstream project is distinct from the native issue tracker.
    public var title: String {
        switch self {
        case .nativeProject: "Project on GitHub"
        case .reportIssue: "Report an Issue"
        case .upstreamWebsite: "Upstream Dust3D Website"
        case .upstreamAcknowledgements: "Upstream Dust3D Acknowledgements"
        case .upstreamSupport: "Support Upstream Dust3D"
        }
    }

    private var address: String? {
        switch self {
        case .nativeProject: "https://github.com/dalbrecht/dust3d-swiftui"
        case .reportIssue: "https://github.com/dalbrecht/dust3d-swiftui/issues/new"
        case .upstreamWebsite: "https://dust3d.org/"
        case .upstreamAcknowledgements: nil
        case .upstreamSupport: "https://fund.dust3d.org/"
        }
    }

    /// Ask macOS to open the selected Help destination and present failures through its standard error UI.
    /// Call only in response to an explicit user command; constructing menus performs no navigation.
    @MainActor public func open() {
        open(using: { NSWorkspace.shared.open($0) }, report: { NSApplication.shared.presentError($0) })
    }

    @MainActor func open(
        applicationBundle: Bundle = .main, developmentBundle: () -> Bundle = { Bundle.module },
        using opener: (URL) -> Bool, report: (ApplicationHelpLinkError) -> Void
    ) {
        if let address {
            if let error = Self.failure(address: address, using: opener) { report(error) }
            return
        }
        let name = "ACKNOWLEDGEMENTS.html"
        let resources = RenderingResourceBundle.resolve(in: applicationBundle, developmentBundle: developmentBundle)
        guard let url = resources?.url(forResource: name, withExtension: nil) else {
            report(.missingBundledResource(name))
            return
        }
        if !opener(url) { report(.openDeclined(url.absoluteString)) }
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
    case missingBundledResource(String)

    var errorDescription: String? {
        switch self {
        case .invalidDestination(let address): "The help link is invalid: \(address)"
        case .openDeclined(let address): "macOS declined to open the help link: \(address)"
        case .missingBundledResource(let name): "The bundled help file \(name) is missing."
        }
    }
}
