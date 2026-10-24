import Foundation
import os

/// One pending notification task; duplicates never accumulate document snapshots or filesystem jobs.
final class EditorRecoveryRequestGate: Sendable {
    private let active = OSAllocatedUnfairLock(initialState: false)

    func begin() -> Bool {
        active.withLock {
            guard !$0 else { return false }
            $0 = true
            return true
        }
    }

    func finish() { active.withLock { $0 = false } }
}

enum EditorRecoveryRequestChannel {

    static func isSupportedIdentity(_ identifier: String) -> Bool {
        ["org.dust3d.editor", "org.dust3d.editor.combine-qa"].contains(identifier)
    }

    static func processIdentifier(_ text: String) -> Int32? {
        guard text.utf8.count <= 10, let value = Int32(text), value > 0, String(value) == text else { return nil }
        return value
    }

    /// Carry only a bounded UUID and exact process identity, never paths, archives or executable commands.
    static func requestID(
        _ notification: Notification, bundleIdentifier: String?,
        processIdentifier: Int32, notificationName: Notification.Name
    ) -> UUID? {
        guard let bundleIdentifier,
            isSupportedIdentity(bundleIdentifier),
            notification.name == notificationName,
            notification.object as? String == bundleIdentifier,
            let info = notification.userInfo, info.count == 2,
            let target = info["processIdentifier"] as? String,
            Self.processIdentifier(target) == processIdentifier,
            let text = info["requestID"] as? String, text.utf8.count == 36,
            let identifier = UUID(uuidString: text), identifier.uuidString.lowercased() == text.lowercased()
        else { return nil }
        return identifier
    }
}
