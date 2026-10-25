import Dust3DKit
import Foundation

/// Original captured source identity, even if a later Open replaces this window's document.
struct EditorExportReceipt: Sendable {
    let documentIdentity: UUID
    let documentRevision: Int
    let destination: URL
    let format: DocumentExportFormat
    let byteCount: Int
    let warning: String
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
