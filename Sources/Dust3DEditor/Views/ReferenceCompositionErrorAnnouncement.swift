import Accessibility
import AppKit
import SwiftUI

struct ReferenceCompositionErrorAnnouncement: NSViewRepresentable {
    let message: String?

    func makeNSView(context: Context) -> ReferenceCompositionErrorAnnouncementAnchor {
        ReferenceCompositionErrorAnnouncementAnchor()
    }

    func updateNSView(_ view: ReferenceCompositionErrorAnnouncementAnchor, context: Context) {
        view.update(message: message, isActive: NSApp.isActive && view.window?.isKeyWindow == true) {
            AccessibilityNotification.Announcement($0).post()
        }
    }
}

final class ReferenceCompositionErrorAnnouncementAnchor: NSView {
    private var previousMessage: String?

    func update(message: String?, isActive: Bool, announce: (String) -> Void) {
        guard message != previousMessage else { return }
        previousMessage = message
        if isActive, let message, !message.isEmpty {
            announce(message)
        }
    }
}
