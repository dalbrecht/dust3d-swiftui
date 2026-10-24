import Foundation

enum EditorRecoveryDispatchError: Error, Equatable, Sendable {
    case invalidCommand, unsupportedIdentity

    var message: String {
        switch self {
        case .invalidCommand:
            "Usage: Dust3DEditor --cancel-reference-composition PID | --write-recovery-copies PID"
        case .unsupportedIdentity:
            "Run recovery using a supported editor app bundle executable."
        }
    }
}

struct EditorRecoveryDispatchRequest: Equatable, Sendable {
    let notificationName: Notification.Name
    let bundleIdentifier: String
    let userInfo: [String: String]
    let acknowledgement: String
    let guidance: String
}

/// Prepare an exact-target request without posting notifications or launching an application.
enum EditorRecoveryDispatchPlan: Equatable, Sendable {
    case application
    case request(EditorRecoveryDispatchRequest)
    case failure(EditorRecoveryDispatchError)

    init(mode: EditorLaunchMode, bundleIdentifier: String?, requestID: UUID) {
        let processIdentifier: Int32
        let isComposition: Bool
        switch mode {
        case .application:
            self = .application
            return
        case .invalidRecoveryCommand:
            self = .failure(.invalidCommand)
            return
        case .cancelComposition(let target):
            processIdentifier = target
            isComposition = true
        case .writeRecoveryCopies(let target):
            processIdentifier = target
            isComposition = false
        }
        guard processIdentifier > 0 else {
            self = .failure(.invalidCommand)
            return
        }
        guard let bundleIdentifier, EditorRecoveryRequestChannel.isSupportedIdentity(bundleIdentifier) else {
            self = .failure(.unsupportedIdentity)
            return
        }
        let operation = isComposition ? "composition cancellation" : "recovery copies"
        self = .request(
            .init(
                notificationName: isComposition
                    ? EditorCompositionRecoveryChannel.notification : EditorRecoveryCopyChannel.notification,
                bundleIdentifier: bundleIdentifier,
                userInfo: ["requestID": requestID.uuidString, "processIdentifier": String(processIdentifier)],
                acknowledgement:
                    "Requested \(operation) in \(bundleIdentifier), PID=\(processIdentifier); requestID=\(requestID.uuidString).",
                guidance: isComposition
                    ? "Dispatch does not confirm cancellation; verify the target process's recovery log or visible sheet state."
                    : "This acknowledges the request only. Check Application Support/\(bundleIdentifier)/RecoveryCopies/latest-recovery.json for this requestID, processIdentifier and results."
            ))
    }
}
