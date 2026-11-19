import Foundation

enum WorkflowReplayStepAnnouncement {
    static func message(step: Int, total: Int, automatic: Bool, active: Bool) -> String? {
        guard active, total > 0, (0...total).contains(step), !automatic || step == total else { return nil }
        if step == 0 { return String(localized: "Ready to replay. Step \(step) of \(total).") }
        if step == total { return String(localized: "Replay complete. Step \(step) of \(total).") }
        return String(localized: "Step \(step) of \(total).")
    }
}
