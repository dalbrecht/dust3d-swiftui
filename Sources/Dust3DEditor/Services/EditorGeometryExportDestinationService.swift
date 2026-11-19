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
    private weak var windowAnchor: NSView?

    var attachedDocument: NSDocument? { windowAnchor?.window?.windowController?.document as? NSDocument }
    var hasActiveDocumentWindow: Bool { NSApp.isActive && windowAnchor?.window?.isKeyWindow == true }

    func trackWindowAnchor(_ anchor: NSView) { windowAnchor = anchor }
    func clearWindowAnchor(_ anchor: NSView) {
        if windowAnchor === anchor { windowAnchor = nil }
    }
    private var panel: NSSavePanel?
    private var isCancelling = false

    func attach(to window: NSWindow) {
        if self.window !== window { cancel() }
        self.window = window
    }

    func chooseDestination(format: DocumentExportFormat = .obj, suggestedName: String) async throws -> URL? {
        try await choose(
            title: "Export \(format.exportName)", message: Self.message(for: format),
            type: Self.contentType(for: format), suggestedName: suggestedName
        ) { try Self.destination(wasAccepted: $0, url: $1, format: format) }
    }

    #if MOTE3D_EXPERIMENTAL_FISH_IDLE && MOTE3D_EXPERIMENTAL_GENERATED_RIG
        func chooseCombinedFishIdleDestination() async throws -> URL? {
            try await choose(
                title: "Export Animated FBX and WAVs",
                message: "Exports a textured animated model and saves sound files beside it.",
                type: Self.contentType(for: .fbx), suggestedName: "Animated Model.fbx"
            ) { try Self.destination(wasAccepted: $0, url: $1, format: .fbx) }
        }

        func chooseWavDestination() async throws -> URL? {
            try await choose(
                title: "Export Animation Sound", message: "Saves the selected animation’s sound as a WAV file.",
                type: .wav, suggestedName: "Animation Sound.wav"
            ) { accepted, url in
                guard accepted else { return nil }
                guard let url else { throw EditorGeometryExportDestinationError.missingDestination }
                return url
            }
        }
    #endif

    private func choose(
        title: String, message: String, type: @autoclosure () throws -> UTType, suggestedName: String,
        destination: @escaping (Bool, URL?) throws -> URL?
    ) async throws -> URL? {
        guard let window else { throw EditorGeometryExportDestinationError.unavailableWindow }
        try Self.validateAvailability(isChoosing: panel != nil, hasAttachedSheet: window.attachedSheet != nil)
        let panel = NSSavePanel()
        panel.title = title
        panel.prompt = "Export"
        panel.message = message
        panel.allowedContentTypes = [try type()]
        panel.allowsOtherFileTypes = false
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = suggestedName
        self.panel = panel
        isCancelling = false
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                panel.beginSheetModal(for: window) { [weak self] response in
                    if self?.panel === panel {
                        self?.panel = nil
                        self?.isCancelling = false
                    }
                    continuation.resume(
                        with: Result { try destination(response == .OK, panel.url) })
                }
            }
        } onCancel: {
            Task { @MainActor [weak self, weak panel] in
                guard let panel, self?.panel === panel else { return }
                self?.cancel()
            }
        }
    }

    static func message(for format: DocumentExportFormat) -> String {
        switch format {
        case .obj, .fbx:
            "Exports original procedural geometry. Materials, textures, rigs and animations are not included. Imported models are unsupported."
        case .fbxTextured:
            "Exports procedural geometry with baked textures and UVs. Imported models, rigs and animations are unsupported."
        }
    }

    func cancel() {
        guard let panel, !isCancelling else { return }
        isCancelling = true
        panel.cancel(nil)
    }

    static func contentType(for format: DocumentExportFormat) throws -> UTType {
        guard let type = UTType(filenameExtension: format.fileExtension) else {
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
        guard url.isFileURL, url.pathExtension.lowercased() == format.fileExtension else {
            throw DocumentExportError.invalidDestination
        }
        return url
    }
}

extension DocumentExportFormat {
    var exportName: String {
        switch self {
        case .obj: "OBJ Geometry"
        case .fbx: "FBX Geometry"
        case .fbxTextured: "Textured FBX"
        }
    }
}
