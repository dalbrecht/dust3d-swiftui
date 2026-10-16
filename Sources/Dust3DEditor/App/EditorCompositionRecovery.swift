import Foundation

/// Recovery uses an explicit, argument-free command; ordinary macOS launch arguments pass through.
enum EditorLaunchMode: Equatable {
    case application
    case cancelComposition
    case invalidRecoveryCommand

    init(arguments: [String]) {
        let command = "--cancel-reference-composition"
        let options = Array(arguments.dropFirst())
        if options == [command] {
            self = .cancelComposition
        } else {
            self = options.contains(command) ? .invalidRecoveryCommand : .application
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

/// The helper process posts only a cancellation request to this app identity in the current login session.
/// No document data, paths or commands are accepted through this channel.
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
            FileHandle.standardError.write(Data("Usage: Dust3DEditor --cancel-reference-composition\n".utf8))
            exit(2)
        }
    }
}
