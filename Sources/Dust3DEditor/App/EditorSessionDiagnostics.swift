import Dust3DRendering
import Foundation
import OSLog
import Observation

/// The editor records only fixed, user-readable outcomes. Reports contain no document or file identifiers.
@MainActor @Observable
final class EditorSessionDiagnostics {
    enum Event: String {
        case documentOpened = "Document opened"
        case documentOpenFailed = "Document could not be opened"
        case previewFailed = "Mesh preview failed"
        case exportCompleted = "Geometry export completed"
        case exportCancellationRequested = "Geometry export cancellation requested"
        case exportFailed = "Geometry export failed"

        var isFailure: Bool {
            switch self {
            case .documentOpenFailed, .previewFailed, .exportFailed: true
            case .documentOpened, .exportCompleted, .exportCancellationRequested: false
            }
        }
    }

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let event: Event
    }

    private static let capacity = 256
    private static let logger = Logger(
        subsystem: RuntimeBuildIdentity.current.loggingSubsystem(fallback: "org.dust3d.editor"),
        category: "SessionDiagnostics")
    private(set) var entries: [Entry] = []

    func record(_ event: Event, at date: Date = .now) {
        if entries.count == Self.capacity { entries.removeFirst() }
        entries.append(Entry(date: date, event: event))
        Self.logger.log(level: event.isFailure ? .error : .info, "\(event.rawValue, privacy: .public)")
    }

    func clear() { entries.removeAll(keepingCapacity: true) }

    var exportText: String {
        entries.map { "\($0.date.formatted(.iso8601))  \($0.event.rawValue)\n" }.joined()
    }
}
