import Foundation

/// Immutable export presentation state, separate from orchestration and view rendering.
enum EditorGeometryExportPhase: Sendable {
    case idle, choosing, encoding, cancelling
    case completed(EditorExportReceipt)
    case failed(any Error)

    var canCancel: Bool {
        switch self {
        case .choosing, .encoding: true
        default: false
        }
    }
}

/// Message identity survives view refreshes, but changes for each actual export.
struct EditorGeometryExportAnnouncement: Equatable {
    let completionID: UUID?
    let message: String
}

extension EditorGeometryExportPhase {
    @MainActor var accessibilityAnnouncement: EditorGeometryExportAnnouncement? {
        switch self {
        case .completed(let receipt):
            EditorGeometryExportAnnouncement(completionID: receipt.id, message: receipt.completionAnnouncement)
        case .failed(let error):
            EditorGeometryExportAnnouncement(completionID: nil, message: "Export failed. " + EditorStore.message(error))
        default: nil
        }
    }
}
