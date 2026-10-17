import AppKit
import Foundation
import SwiftUI

@MainActor enum InspectorRenderer {
    enum Failure: Error, Equatable { case invalidSize, bitmapUnavailable, encodingUnavailable, visibleWindow }

    static func png<Content: View>(_ content: Content, width: CGFloat, scheme: ColorScheme) throws -> Data {
        guard width.isFinite, width > 0, width <= 1000 else { throw Failure.invalidSize }
        // This artifact-exporting test process must never appear in the Dock or activate a product app.
        NSApplication.shared.setActivationPolicy(.prohibited)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 1000),
            styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer {
            window.contentView = nil
            window.close()
        }
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.appearance = appearance
        let root = content.padding(16).frame(width: width, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, scheme).environment(\.displayScale, 2)
        let hosting = NSHostingView(rootView: root)
        hosting.appearance = appearance
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 1000)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        // SwiftUI initial state updates must settle before measuring the full scroll-content height.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        hosting.layoutSubtreeIfNeeded()
        let height = ceil(hosting.fittingSize.height)
        guard height.isFinite, height > 0, height <= 4096 else { throw Failure.invalidSize }
        window.setContentSize(NSSize(width: width, height: height))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hosting.layoutSubtreeIfNeeded()
        guard !window.isVisible else { throw Failure.visibleWindow }
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw Failure.bitmapUnavailable
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw Failure.encodingUnavailable }
        return data
    }
}
