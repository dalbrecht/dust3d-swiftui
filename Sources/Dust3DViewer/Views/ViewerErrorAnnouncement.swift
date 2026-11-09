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

    func update(message: String?, materialIssue: String? = nil, isActive: Bool, announce: (String) -> Void) {
        let newMessage = message != previousMessage ? message : nil
        let newMaterialIssue = materialIssue != previousMaterialIssue ? materialIssue : nil
        previousMessage = message
        previousMaterialIssue = materialIssue
        guard isActive else { return }
        if let newMessage, !newMessage.isEmpty {
            announce(newMessage)
        } else if let newMaterialIssue, !newMaterialIssue.isEmpty {
            announce(ViewerErrorAnnouncement.materialFallbackTitle + ". " + newMaterialIssue)
        }
    }
}
