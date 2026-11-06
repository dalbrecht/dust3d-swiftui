import AppKit
import Foundation

/// Native application information; immutable build/source diagnostics remain a separate window.
@MainActor public enum ApplicationAboutPanel {
    /// Display AppKit's standard panel using the app's packaged icon/version and QA-aware name.
    /// The platform owns the panel's lifecycle. Calling this method is a user interface action.
    public static func show(applicationName: String) {
        NSApplication.shared.orderFrontStandardAboutPanel(options: options(applicationName: applicationName))
    }

    static func options(applicationName: String) -> [NSApplication.AboutPanelOptionKey: Any] {
        options(
            applicationName: applicationName,
            licenseURL: Bundle.module.url(forResource: "ApplicationLicense", withExtension: "txt"),
            contributorsURL: Bundle.module.url(forResource: "ApplicationContributors", withExtension: "txt"),
            supportersURL: Bundle.module.url(forResource: "ApplicationSupporters", withExtension: "txt"))
    }

    static func options(
        applicationName: String, licenseURL: URL?, contributorsURL: URL? = nil, supportersURL: URL? = nil
    ) -> [NSApplication.AboutPanelOptionKey: Any] {
        let license = resourceText(at: licenseURL, resource: "ApplicationLicense.txt", title: "License")
        let contributors = resourceText(
            at: contributorsURL, resource: "ApplicationContributors.txt", title: "Contributors")
        let supporters = resourceText(at: supportersURL, resource: "ApplicationSupporters.txt", title: "Supporters")
        let credits = license + "\n\nContributors\n\n" + contributors + "\n\nSupporters\n\n" + supporters
        var result: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: applicationName,
            .credits: NSAttributedString(string: credits),
        ]
        if let copyright = license.split(separator: "\n").first(where: { $0.hasPrefix("Copyright") }) {
            // AppKit documents this additional dictionary key alongside AboutPanelOptionKey.
            result[NSApplication.AboutPanelOptionKey(rawValue: "Copyright")] = String(copyright)
        }
        return result
    }

    private static func resourceText(at url: URL?, resource: String, title: String) -> String {
        guard let url else {
            return
                "\(title) information unavailable: the bundled \(resource) file is missing."
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            return "Unable to read \(resource): \(error.localizedDescription)"
        }
    }
}
