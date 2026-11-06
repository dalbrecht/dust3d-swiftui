import Dust3DKit
import Foundation

/// Original captured source identity, even if a later Open replaces this window's document.
struct EditorExportReceipt: Sendable {
    /// Distinguish repeated exports of the same revision/destination after UI update coalescing.
    let id = UUID()
    let documentIdentity: UUID
    let documentRevision: Int
    let destination: URL
    let format: DocumentExportFormat
    let byteCount: Int
    let warning: String

    var completionAnnouncement: String {
        let result = "Exported \(destination.lastPathComponent)."
        return warning.isEmpty ? result : result + " Export warning: " + warning
    }
}

/// Workflow admission failures; native, document and filesystem errors retain their original types.
enum EditorExportWorkflowError: LocalizedError, Equatable {
    case unavailable, notReady

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Export is not available in this build."
        case .notReady: return "Open a document and finish the current operation before exporting."
        }
    }
}
