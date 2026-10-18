import AppKit
import Dust3DRendering
import QuickLookUI
import SwiftUI

/// Quick Look's required AppKit boundary hosts shared read-only SwiftUI content.
final class PreviewViewController: NSViewController, QLPreviewingController {
    private let service = FilePreviewDocumentService()
    private var generation: Task<FilePreviewDocument, any Error>?
    private var requestID = UUID()

    override func loadView() { view = NSView(frame: CGRect(x: 0, y: 0, width: 640, height: 480)) }

    func preparePreviewOfFile(at url: URL) async throws {
        generation?.cancel()
        let request = UUID()
        requestID = request
        for child in children {
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
        let operation = Task { [service] in try await service.load(url: url) }
        generation = operation
        let document = try await withTaskCancellationHandler {
            try await operation.value
        } onCancel: {
            operation.cancel()
        }
        try Task.checkCancellation()
        guard requestID == request else { throw CancellationError() }
        let content = NSHostingController(rootView: FilePreviewView(document: document))
        addChild(content)
        content.view.frame = view.bounds
        content.view.autoresizingMask = [.width, .height]
        view.addSubview(content.view)
        preferredContentSize = CGSize(width: 640, height: 480)
        generation = nil
    }

    deinit { generation?.cancel() }
}
