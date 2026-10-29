import AppKit
import Dust3DKit
import UniformTypeIdentifiers

/// Original panel admission failures are surfaced by the owning workflow.
enum EditorGeometryExportDestinationError: LocalizedError, Equatable {
    case unavailableWindow, alreadyChoosing, anotherSheetActive, unavailableFileType, missingDestination

    var errorDescription: String? {
        switch self {
        case .unavailableWindow: "The document window is not ready to export. Try again."
        case .alreadyChoosing: "An export destination dialog is already open."
        case .anotherSheetActive: "Finish or cancel the current dialog before exporting."
        case .unavailableFileType: "This Mac could not provide the selected export file type."
        case .missingDestination: "The export dialog did not return a destination."
        }
    }
}

/// Keeps native presentation narrow; the existing file service owns publication.
@MainActor
final class EditorGeometryExportDestinationService: EditorGeometryExportDestinationChoosing {
    private weak var window: NSWindow?
    private var panel: NSSavePanel?
    private var isCancelling = false

    func attach(to window: NSWindow) {
        if self.window !== window { cancel() }
        self.window = window
    }

    func chooseDestination(format: DocumentExportFormat = .obj, suggestedName: String) async throws -> URL? {
        guard let window else { throw EditorGeometryExportDestinationError.unavailableWindow }
        try Self.validateAvailability(isChoosing: panel != nil, hasAttachedSheet: window.attachedSheet != nil)
        let type = try Self.contentType(for: format)
        let panel = NSSavePanel()
        panel.title = "Export \(format.rawValue.uppercased()) Geometry"
        panel.prompt = "Export"
        panel.message =
            "Exports original procedural geometry. Materials, textures, rigs and animations are not included. Imported models are unsupported."
        panel.allowedContentTypes = [type]
        panel.allowsOtherFileTypes = false
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = suggestedName
        self.panel = panel
        isCancelling = false
        return try await withCheckedThrowingContinuation { continuation in
            panel.beginSheetModal(for: window) { [weak self] response in
                if self?.panel === panel {
                    self?.panel = nil
                    self?.isCancelling = false
                }
                continuation.resume(
                    with: Result { try Self.destination(wasAccepted: response == .OK, url: panel.url, format: format) })
            }
        }
    }

    func cancel() {
        guard let panel, !isCancelling else { return }
        isCancelling = true
        panel.cancel(nil)
    }

    static func contentType(for format: DocumentExportFormat) throws -> UTType {
        guard let type = UTType(filenameExtension: format.rawValue) else {
            throw EditorGeometryExportDestinationError.unavailableFileType
        }
        return type
    }

    static func validateAvailability(isChoosing: Bool, hasAttachedSheet: Bool) throws {
        guard !isChoosing else { throw EditorGeometryExportDestinationError.alreadyChoosing }
        guard !hasAttachedSheet else { throw EditorGeometryExportDestinationError.anotherSheetActive }
    }

    static func destination(wasAccepted: Bool, url: URL?, format: DocumentExportFormat = .obj) throws -> URL? {
        guard wasAccepted else { return nil }
        guard let url else { throw EditorGeometryExportDestinationError.missingDestination }
        guard url.isFileURL, url.pathExtension.lowercased() == format.rawValue else {
            throw DocumentExportError.invalidDestination
        }
        return url
    }
}
