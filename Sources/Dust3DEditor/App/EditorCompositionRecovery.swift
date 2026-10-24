import Foundation

/// Recovery accepts only explicit bounded commands; ordinary macOS launch arguments pass through.
enum EditorLaunchMode: Equatable {
    case application
    case cancelComposition
    case writeRecoveryCopies(processIdentifier: Int32)
    case invalidRecoveryCommand

    init(arguments: [String]) {
        let command = "--cancel-reference-composition"
        let copies = "--write-recovery-copies"
        let options = Array(arguments.dropFirst())
        if options == [command] {
            self = .cancelComposition
        } else if options.count == 2, options[0] == copies,
            let processIdentifier = EditorRecoveryCopyChannel.processIdentifier(options[1])
        {
            self = .writeRecoveryCopies(processIdentifier: processIdentifier)
        } else {
            self = options.contains(command) || options.contains(copies) ? .invalidRecoveryCommand : .application
        }
    }
}

/// Routes recovery to one transient sheet. A busy sheet must never cause another document to be cancelled.
@MainActor final class EditorCompositionRecovery {
    static let shared = EditorCompositionRecovery()
    static let notification = Notification.Name("org.dust3d.editor.cancel-reference-composition")
    private var presentations: [(identifier: UUID, cancel: @MainActor () -> Bool)] = []

    func register(_ identifier: UUID, cancel: @escaping @MainActor () -> Bool) {
        unregister(identifier)
        presentations.append((identifier, cancel))
    }

    func unregister(_ identifier: UUID) {
        presentations.removeAll { $0.identifier == identifier }
    }

    @discardableResult func cancelLatest() -> Bool {
        presentations.last?.cancel() ?? false
    }
}

/// Posts bounded recovery requests; copy requests require an exact process identity.
/// No document data or destination paths are accepted through these channels.
@main enum Dust3DEditorEntryPoint {
    @MainActor static func main() {
        switch EditorLaunchMode(arguments: CommandLine.arguments) {
        case .application:
            Dust3DEditorApp.main()
        case .cancelComposition:
            guard let identifier = Bundle.main.bundleIdentifier else {
                FileHandle.standardError.write(Data("Run recovery using the editor app bundle executable.\n".utf8))
                exit(2)
            }
            DistributedNotificationCenter.default().postNotificationName(
                EditorCompositionRecovery.notification, object: identifier, userInfo: nil, deliverImmediately: true)
            print("Requested cancellation of the most recently opened composition sheet in \(identifier).")
        case .invalidRecoveryCommand:
            FileHandle.standardError.write(
                Data("Usage: Dust3DEditor --cancel-reference-composition | --write-recovery-copies PID\n".utf8))
            exit(2)
        case .writeRecoveryCopies(let processIdentifier):
            guard let identifier = Bundle.main.bundleIdentifier,
                EditorRecoveryCopyChannel.isSupportedIdentity(identifier)
            else {
                FileHandle.standardError.write(
                    Data("Run recovery using a supported editor app bundle executable.\n".utf8))
                exit(2)
            }
            let requestID = UUID()
            DistributedNotificationCenter.default().postNotificationName(
                EditorRecoveryCopyChannel.notification, object: identifier,
                userInfo: ["requestID": requestID.uuidString, "processIdentifier": String(processIdentifier)],
                deliverImmediately: true)
            print(
                "Requested recovery copies in \(identifier), PID=\(processIdentifier); requestID=\(requestID.uuidString)."
            )
            print(
                "This acknowledges the request only. Check Application Support/\(identifier)/RecoveryCopies/latest-recovery.json for this requestID, processIdentifier and results."
            )
        }
    }
}
