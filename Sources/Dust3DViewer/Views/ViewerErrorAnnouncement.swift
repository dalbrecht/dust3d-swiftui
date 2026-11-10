import Accessibility
import AppKit
import SwiftUI

struct ViewerErrorAnnouncement: NSViewRepresentable {
    static let materialFallbackTitle = String(localized: "Showing geometry without materials")

    let message: String?
    let materialIssue: String?

    func makeNSView(context: Context) -> ViewerErrorAnnouncementAnchor {
        ViewerErrorAnnouncementAnchor()
    }

    func updateNSView(_ view: ViewerErrorAnnouncementAnchor, context: Context) {
        view.update(
            message: message, materialIssue: materialIssue,
            isActive: NSApp?.isActive == true && view.window?.isKeyWindow == true
        ) {
            AccessibilityNotification.Announcement($0).post()
        }
    }
}

final class ViewerErrorAnnouncementAnchor: NSView {
    private var previousMessage: String?
    private var previousMaterialIssue: String?
    private var pendingMaterialIssue: String?

    func update(message: String?, materialIssue: String? = nil, isActive: Bool, announce: (String) -> Void) {
        let newMessage = message != previousMessage ? message : nil
        let materialIssueChanged = materialIssue != previousMaterialIssue
        previousMessage = message
        previousMaterialIssue = materialIssue
        guard isActive else {
            pendingMaterialIssue = nil
            return
        }
        if materialIssueChanged {
            pendingMaterialIssue = materialIssue
        }
        // Keep the latest fallback available until the higher-priority error clears.
        if let message, !message.isEmpty {
            if let newMessage {
                announce(newMessage)
            }
            return
        }
        guard let pendingMaterialIssue, !pendingMaterialIssue.isEmpty else { return }
        self.pendingMaterialIssue = nil
        announce(ViewerErrorAnnouncement.materialFallbackTitle + ". " + pendingMaterialIssue)
    }
}
