import Foundation

/// Recovery accepts only explicit bounded commands; ordinary macOS launch arguments pass through.
enum EditorLaunchMode: Equatable {
    case application
    case cancelComposition(processIdentifier: Int32)
    case writeRecoveryCopies(processIdentifier: Int32)
    case invalidRecoveryCommand

    init(arguments: [String]) {
        let command = "--cancel-reference-composition"
        let copies = "--write-recovery-copies"
        let options = Array(arguments.dropFirst())
        if options.count == 2, [command, copies].contains(options[0]),
            let processIdentifier = EditorRecoveryRequestChannel.processIdentifier(options[1])
        {
            self =
                options[0] == command
                ? .cancelComposition(processIdentifier: processIdentifier)
                : .writeRecoveryCopies(processIdentifier: processIdentifier)
        } else {
            self = options.contains(command) || options.contains(copies) ? .invalidRecoveryCommand : .application
        }
    }
}

enum EditorCompositionRecoveryChannel {
    // A new name keeps legacy receivers, which ignore request metadata, outside this protocol.
    static let notification = Notification.Name("org.dust3d.editor.cancel-reference-composition.v2")
}

/// Routes recovery to one transient sheet. A busy sheet must never cause another document to be cancelled.
@MainActor final class EditorCompositionRecovery {
    static let shared = EditorCompositionRecovery()
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

/// Posts bounded recovery requests requiring an exact process identity.
/// No document data or destination paths are accepted through these channels.
@main enum Dust3DEditorEntryPoint {
    @MainActor static func main() {
        let plan = EditorRecoveryDispatchPlan(
            mode: EditorLaunchMode(arguments: CommandLine.arguments),
            bundleIdentifier: Bundle.main.bundleIdentifier, requestID: UUID())
        switch plan {
        case .application:
            Dust3DEditorApp.main()
        case .request(let request):
            DistributedNotificationCenter.default().postNotificationName(
                request.notificationName, object: request.bundleIdentifier,
                userInfo: request.userInfo, deliverImmediately: true)
            print(request.acknowledgement)
            print(request.guidance)
        case .failure(let error):
            FileHandle.standardError.write(Data((error.message + "\n").utf8))
            exit(2)
        }
    }
}
