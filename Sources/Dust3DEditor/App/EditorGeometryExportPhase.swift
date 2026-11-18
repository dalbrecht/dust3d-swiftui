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
    @MainActor func editorErrorAnnouncement(_ message: String?, isKeyWindow: Bool) -> String? {
        guard isKeyWindow, let message, !message.isEmpty else { return nil }
        if case .failed(let error) = self, EditorStore.message(error) == message { return nil }
        return message
    }

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
