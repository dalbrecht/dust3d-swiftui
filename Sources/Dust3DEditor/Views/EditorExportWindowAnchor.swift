import AppKit
import SwiftUI

/// Binds the panel to its document window instead of a process-global key window.
@MainActor
struct EditorExportWindowAnchor: NSViewRepresentable {
    let service: EditorGeometryExportDestinationService

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.service = service
        service.trackWindowAnchor(view)
        return view
    }

    func updateNSView(_ view: AnchorView, context: Context) {
        view.service = service
        service.trackWindowAnchor(view)
        if let window = view.window { service.attach(to: window) }
    }

    static func dismantleNSView(_ view: AnchorView, coordinator: ()) {
        // Root lifetime owns cancellation; an old anchor must not detach a newer window.
        view.service?.clearWindowAnchor(view)
        view.service = nil
    }

    final class AnchorView: NSView {
        weak var service: EditorGeometryExportDestinationService?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { service?.attach(to: window) }
        }
    }
}
