import Foundation

/// Resolve installed app resources before considering a development-only SwiftPM accessor.
enum RenderingResourceBundle {
    static func resolve(in applicationBundle: Bundle, developmentBundle: () -> Bundle) -> Bundle? {
        if let url = applicationBundle.resourceURL?.appendingPathComponent("Dust3DNative_Dust3DRendering.bundle"),
            let packaged = Bundle(url: url)
        {
            return packaged
        }
        // SwiftPM's accessor can terminate when its absolute build path is gone.
        // An installed app reports missing attribution instead of consulting that path.
        guard applicationBundle.bundleURL.pathExtension.lowercased() != "app" else { return nil }
        return developmentBundle()
    }
}
