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
            licenseURL: Bundle.module.url(forResource: "ApplicationLicense", withExtension: "txt"))
    }

    static func options(applicationName: String, licenseURL: URL?) -> [NSApplication.AboutPanelOptionKey: Any] {
        let license = licenseText(at: licenseURL)
        var result: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: applicationName,
            .credits: NSAttributedString(string: license),
        ]
        if let copyright = license.split(separator: "\n").first(where: { $0.hasPrefix("Copyright") }) {
            // AppKit documents this additional dictionary key alongside AboutPanelOptionKey.
            result[NSApplication.AboutPanelOptionKey(rawValue: "Copyright")] = String(copyright)
        }
        return result
    }

    private static func licenseText(at url: URL?) -> String {
        guard let url else {
            return
                "License information unavailable: the bundled ApplicationLicense.txt file is missing."
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            return "Unable to read ApplicationLicense.txt: \(error.localizedDescription)"
        }
    }
}
