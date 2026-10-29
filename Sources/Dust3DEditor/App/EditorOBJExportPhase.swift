/// Immutable export presentation state, separate from orchestration and view rendering.
enum EditorOBJExportPhase: Sendable {
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
