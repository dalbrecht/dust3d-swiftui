import CoreGraphics
import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import Observation

@MainActor @Observable
final class EditorStore {
    private(set) var snapshot: EditorSnapshot?
    private(set) var isWorking = false { didSet { onEditingChanged?(isWorking) } }
    private(set) var previewState = MeshPreviewState<Mesh>()
    var mesh: Mesh? { previewState.value }
    var previewRevision: Int { previewState.revision }
    var isGenerating: Bool { previewState.isGenerating }
    var errorMessage: String?
    var renderError: String?
    var bounds = CanvasBounds(nodes: [])
    var plane = EditingPlane.front { didSet { if plane != oldValue { cancelOriginDrag() } } }
    private(set) var isMovingOrigin = false
    private(set) var originDragPosition: NodePosition?
    private var originDrag: OriginDrag?
    var isWireframe = false
    var cameraReset = 0
    private(set) var referenceImage: CGImage?
    private(set) var referenceImageError: String?
    private(set) var isLoadingReferenceImage = false
    var showsReferenceImage = true
    var referenceImageOpacity = 0.5
    var hasReferenceImage: Bool { snapshot?.document.hasReferenceImage == true }
    var referenceImageForComposition: CGImage? {
        guard hasReferenceImage, !isLoadingReferenceImage, referenceImageError == nil else { return nil }
        return referenceImage
    }
    var onDocumentChanged: ((Data) -> Void)?
    var onEditingChanged: ((Bool) -> Void)?
    private let session = EditorSession()
    private let preview = EditorPreviewService()
    private let referenceImages: any ReferenceImageServing
    private var operation: Task<Void, Never>?
    private var generation: Task<Void, Never>?
    private var referenceGeneration: Task<Void, Never>?
    private var referenceRequestID = UUID()
    private var stopped = false

    init(referenceImages: any ReferenceImageServing = ReferenceImageService()) {
        self.referenceImages = referenceImages
    }

    var locks: Set<EditingConstraint> { snapshot?.locks ?? [] }
    var canSave: Bool { snapshot != nil && !isWorking && !stopped }
    var canUndo: Bool { !isWorking && snapshot?.canUndo == true }
    var canRedo: Bool { !isWorking && snapshot?.canRedo == true }

    func load(data: Data) async {
        cancelOriginDrag()
        stopped = false
        isWorking = true
        defer { isWorking = false }
        do {
            let next = try await session.open(data: data)
            guard !Task.isCancelled, !stopped else { return }
            snapshot = next
            referenceImage = nil
            fit()
            previewState.clear()
            generate(next)
            refreshReferenceImage(next, forceFit: true)
        } catch {
            if !Task.isCancelled { errorMessage = Self.message(error) }
        }
    }

    func setMovingOrigin(_ enabled: Bool) {
        cancelOriginDrag()
        isMovingOrigin = enabled && !isWorking && !stopped && snapshot?.origin != nil
    }

    func cancelOriginDrag() {
        isMovingOrigin = false
        originDrag = nil
        originDragPosition = nil
    }

    func updateOriginDrag(translation: CanvasPoint, projection: CanvasProjection) {
        guard isMovingOrigin, !isWorking, !stopped, let snapshot else { return }
        do {
            let baseline = try originDrag ?? OriginDrag(snapshot: snapshot, projection: projection)
            guard baseline.isCurrent(in: snapshot) else {
                cancelOriginDrag()
                return
            }
            let position = baseline.position(by: translation)
            guard [translation.x, translation.y, position.x, position.y, position.z].allSatisfy(\.isFinite),
                [position.x, position.y, position.z].allSatisfy({ abs($0) <= 1_000_000 })
            else { throw DocumentError.invalidOrigin }
            originDrag = baseline
            originDragPosition = position
        } catch {
            cancelOriginDrag()
            errorMessage = Self.message(error)
        }
    }

    func finishOriginDrag(translation: CanvasPoint) {
        guard isMovingOrigin, let baseline = originDrag else { return }
        perform { try await $0.commitOriginDrag(baseline, translation: translation) }
    }

    func setLock(_ constraint: EditingConstraint, isLocked: Bool) {
        perform(commits: false) { try await $0.setLock(constraint, isLocked: isLocked) }
    }

    func select(_ id: String?) { perform(commits: false) { try await $0.select(id) } }

    func select(_ ids: Set<String>) { perform(commits: false) { try await $0.select(ids) } }
    func selectEdge(_ id: String?) { perform(commits: false) { try await $0.selectEdge(id) } }
    func selectPart(_ id: String?) { perform(commits: false) { try await $0.selectPart(id) } }
    func setOrigin(x: String, y: String, z: String) {
        guard !isWorking, !stopped else { return }
        guard let x = Double(x), let y = Double(y), let z = Double(z) else {
            errorMessage = Self.message(DocumentError.invalidOrigin)
            return
        }
        perform { try await $0.apply([.setOrigin(.init(x: x, y: y, z: z))]) }
    }
    func centerOriginOnModel() {
        perform { try await $0.centerOriginOnModel() }
    }
    func renamePart(_ id: String, name: String) {
        perform(regenerateMesh: false) { try await $0.apply([.setPartName(id: id, name: name)]) }
    }
    func setPartState(_ id: String, property: PartStateProperty, value: Bool) {
        perform(regenerateMesh: property == .disabled) {
            try await $0.apply([.setPartState(id: id, property: property, value: value)])
        }
    }
    func toggleSelection(_ id: String) { perform(commits: false) { try await $0.toggleSelection(id) } }
    func selectAll() { perform(commits: false) { try await $0.selectAll() } }
    func move(id: String, to position: NodePosition) { perform { try await $0.move(id: id, to: position) } }
    func moveSelection(by delta: NodePosition) { perform { try await $0.moveSelection(by: delta) } }
    func scaleSelection(positionFactor: Double, radiusFactor: Double) {
        perform { try await $0.scaleSelection(positionFactor: positionFactor, radiusFactor: radiusFactor) }
    }
    var canTransform: Bool { !isWorking && snapshot?.selectedNodes.contains(where: \.isEditable) == true }
    var canRotateDescendants: Bool { !isWorking && snapshot?.canRotateDescendants == true }
    func rotateDescendants(_ rotation: DescendantRotation) { perform { try await $0.rotateDescendants(rotation) } }
    func transformSelection(_ transform: SelectionTransform) { perform { try await $0.transformSelection(transform) } }
    func reverseSelectedEdges() { perform { try await $0.reverseSelectedEdges() } }
    func reverseEdge(_ id: String) { perform { try await $0.apply([.reverseEdges([id])]) } }

    var canCopyNodes: Bool { !isWorking && snapshot?.canCopyNodes == true }
    var canCutNodes: Bool { !isWorking && snapshot?.canCutNodes == true }

    /// Clipboard promise registration succeeds before a Cut can mutate the document.
    func copyNodes(cut: Bool = false, to pasteboard: EditorPasteboard) {
        guard cut ? canCutNodes : canCopyNodes, !stopped else { return }
        cancelOriginDrag()
        isWorking = true
        operation = Task {
            defer { isWorking = false }
            do {
                let data = try await session.copyRepresentations(identifier: UUID().uuidString, onlyEditable: cut)
                guard !Task.isCancelled, !stopped else { return }
                try pasteboard.write(data.native, snapshotXML: data.snapshotXML)
                if cut {
                    let next = try await session.deleteSelection()
                    guard !Task.isCancelled, !stopped else { return }
                    snapshot = next
                    fit()
                    onDocumentChanged?(next.document.encoded())
                    generate(next)
                }
                errorMessage = nil
            } catch {
                if !Task.isCancelled { errorMessage = Self.message(error) }
            }
        }
    }

    /// The system PasteButton delivers data asynchronously; the session validates it away from the UI actor.
    func pasteNodes(data: Data) {
        perform(reloadReferenceImage: true) { try await $0.paste(data: data) }
    }

    func pasteQtNodes(snapshotXML: Data) {
        perform(reloadReferenceImage: true) { try await $0.paste(snapshotXML: snapshotXML) }
    }

    func deleteSelection() { perform { try await $0.deleteSelection() } }

    func edit(id: String, position: NodePosition, radius: Double) {
        perform { try await $0.edit(id: id, position: position, radius: radius) }
    }

    var canAddNode: Bool { !isWorking && snapshot?.canAddNode == true }

    func addNode(newPart: Bool = false) {
        guard let snapshot, newPart || canAddNode else { return }
        let selected = newPart ? nil : snapshot.selectedNode
        let nodeID = Self.identifier()
        let partID = selected?.partID ?? Self.identifier()
        let position = newPart ? NodePosition(x: 0.5, y: 0.5, z: 0.5) : snapshot.nextNodePosition
        var commands: [DocumentCommand] = [
            .addNode(
                id: nodeID, partID: partID, componentID: selected?.partID == nil ? Self.identifier() : nil,
                position: position, radius: selected?.value.radius ?? 0.1)
        ]
        if let selected, selected.partID != nil {
            commands.append(.joinNodes(id: Self.identifier(), from: selected.id, to: nodeID))
        }
        let transaction = commands
        perform { try await $0.apply(transaction, selecting: nodeID) }
    }

    func connect(to id: String) {
        guard let selected = snapshot?.selectedID else { return }
        let command = DocumentCommand.joinNodes(id: Self.identifier(), from: selected, to: id)
        perform { try await $0.apply([command]) }
    }

    func deleteNode() {
        guard let id = snapshot?.selectedID else { return }
        perform { try await $0.apply([.removeNode(id: id)]) }
    }

    func deleteEdge(_ id: String) { perform { try await $0.apply([.removeEdge(id: id)]) } }

    private static func identifier() -> String { "{\(UUID().uuidString.lowercased())}" }

    func undo() { perform(reloadReferenceImage: true) { try await $0.undo() } }
    func redo() { perform(reloadReferenceImage: true) { try await $0.redo() } }

    /// The sheet waits for publication before dismissing; validation errors keep its draft available.
    func applyReferenceComposition(
        _ result: ReferenceCompositionResult, target: ReferenceCompositionTarget, setsOrigin: Bool
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            perform(
                reloadReferenceImage: true, regenerateMesh: setsOrigin,
                completion: { continuation.resume(returning: $0) }
            ) { session in
                try await session.applyReferenceComposition(
                    png: result.png, origin: setsOrigin ? result.layout.origin : nil, target: target)
            }
        }
    }

    func importReferenceImage(from url: URL) {
        let service = referenceImages
        perform(reloadReferenceImage: true, regenerateMesh: false) { session in
            let png = try await service.importImage(url: url)
            return try await session.apply([.setReferenceImagePNG(png)])
        }
    }

    func removeReferenceImage() {
        perform(reloadReferenceImage: true, regenerateMesh: false) { try await $0.apply([.setReferenceImagePNG(nil)]) }
    }

    func fit() {
        cancelOriginDrag()
        fitCanvas()
        cameraReset += 1
    }

    private func fitCanvas() {
        cancelOriginDrag()
        let aspect = showsReferenceImage ? referenceImage.map { Double($0.width) / Double($0.height) } : nil
        bounds = CanvasBounds(nodes: snapshot?.nodes ?? [], referenceImageAspectRatio: aspect, origin: snapshot?.origin)
    }

    func stop() {
        cancelOriginDrag()
        stopped = true
        operation?.cancel()
        generation?.cancel()
        referenceGeneration?.cancel()
        previewState.clear()
        onDocumentChanged = nil
        onEditingChanged?(false)
        onEditingChanged = nil
    }

    private func perform(
        commits: Bool = true, reloadReferenceImage: Bool = false, regenerateMesh: Bool = true,
        completion: (@MainActor (Bool) -> Void)? = nil,
        _ action: @escaping @Sendable (EditorSession) async throws -> EditorSnapshot
    ) {
        guard !isWorking, !stopped else {
            completion?(false)
            return
        }
        cancelOriginDrag()
        isWorking = true
        operation = Task {
            var succeeded = false
            defer {
                isWorking = false
                completion?(succeeded)
            }
            do {
                let next = try await action(session)
                guard !Task.isCancelled, !stopped else { return }
                let changed = next.documentRevision != snapshot?.documentRevision
                // Visibility changes need fitting even when topology is unchanged; movements keep stable drag bounds.
                let countChanged = next.nodes.count != snapshot?.nodes.count
                let needsFit =
                    next.origin != snapshot?.origin
                    || !next.nodes.elementsEqual(snapshot?.nodes ?? []) {
                        $0.id == $1.id && $0.isVisible == $1.isVisible
                    }
                snapshot = next
                if countChanged {
                    fit()
                } else if needsFit {
                    fitCanvas()
                }
                errorMessage = nil
                if commits && changed {
                    onDocumentChanged?(next.document.encoded())
                    if regenerateMesh { generate(next) }
                    if reloadReferenceImage { refreshReferenceImage(next) }
                }
                succeeded = true
            } catch {
                if !Task.isCancelled { errorMessage = Self.message(error) }
            }
        }
    }

    private func generate(_ snapshot: EditorSnapshot) {
        generation?.cancel()
        renderError = nil
        guard snapshot.hasEnabledGeometry else {
            previewState.clear()
            return
        }
        let requestID = UUID()
        previewState.begin(requestID: requestID)
        generation = Task {
            do {
                try await Task.sleep(for: .milliseconds(150))
                let result = try await preview.generate(snapshot.document.encoded())
                // Asset-only edits can advance document revision without changing geometry; request identity wins.
                guard !Task.isCancelled, !stopped else {
                    return
                }
                previewState.succeed(result, requestID: requestID)
            } catch {
                guard !Task.isCancelled, !stopped else { return }
                previewState.fail(Self.message(error), requestID: requestID)
            }
        }
    }

    func retryPreview() {
        guard !stopped, !isGenerating, let snapshot else { return }
        generate(snapshot)
    }

    private func refreshReferenceImage(_ snapshot: EditorSnapshot, forceFit: Bool = false) {
        referenceGeneration?.cancel()
        let requestID = UUID()
        referenceRequestID = requestID
        referenceImageError = nil
        isLoadingReferenceImage = true
        let hadImage = referenceImage != nil
        if !snapshot.document.hasReferenceImage {
            referenceImage = nil
            if hadImage { fit() }
        }
        referenceGeneration = Task {
            do {
                let result = try await referenceImages.preview(document: snapshot.document)
                guard !Task.isCancelled, !stopped, referenceRequestID == requestID else { return }
                referenceImage = result.image
                isLoadingReferenceImage = false
                // Empty results only clear the cache; Load/removal already fitted their visible content.
                if result.image != nil && (result.changed || forceFit || !hadImage) { fit() }
            } catch {
                guard !Task.isCancelled, !stopped, referenceRequestID == requestID else { return }
                referenceImage = nil
                referenceImageError = Self.message(error)
                isLoadingReferenceImage = false
                if hadImage { fit() }
            }
        }
    }

    static func message(_ error: Error) -> String {
        if let image = error as? ReferenceImageError {
            switch image {
            case .invalidImage:
                return "The reference image could not be decoded. Its existing archive bytes remain preserved."
            case .unsupportedFormat: return "Choose a PNG, JPEG, BMP, GIF or TIFF reference image."
            case .imageTooLarge:
                return "Reference images are limited to 32 MiB, 8192 pixels per side and 16 megapixels."
            case .conversionFailed: return "The reference image could not be converted to PNG."
            case .fileReadFailed(let cause): return "The reference image could not be read: \(cause)"
            }
        }
        if let composition = error as? ReferenceCompositionError {
            switch composition {
            case .invalidDimensions: return "Use positive source dimensions within the reference-image limits."
            case .invalidCrop: return "Enter a nonempty crop fully inside the source image."
            case .emptyComposition: return "Import a Front or Side image before applying."
            case .outputTooLarge:
                return "This crop would produce a turnaround wider than 8192 pixels. Use a taller or narrower crop."
            }
        }
        if let document = error as? DocumentError {
            switch document {
            case .invalidArchive: return "This file is not a supported Dust3D 1.0 archive."
            case .invalidXML: return "The document contains invalid or unsupported XML."
            case .invalidOrigin: return "Enter finite origin coordinates within ±1,000,000."
            case .invalidReferenceImage: return "The reference image must contain PNG data."
            case .limitExceeded: return "The document or edit exceeds supported size or undo-history limits."
            case .missingNode(let id): return "Node \(id) is not present in this document."
            case .missingPart(let id): return "Part \(id) is not present in this document."
            case .invalidPartName: return "Use a single-line part name of at most 1024 UTF-8 bytes."
            case .invalidNode: return "The document contains invalid node, part, or edge data."
            case .conflictingAsset(let name): return "Clipboard asset \(name) conflicts with this document."
            case .cyclicProfile: return "This edit would create a cyclic cut-face reference."
            case .transactionAlreadyOpen: return "An edit transaction is already in progress."
            case .noTransaction: return "No edit transaction is in progress."
            }
        }
        if let clipboard = error as? ClipboardError {
            switch clipboard {
            case .invalidPayload: return "The clipboard contains invalid Dust3D node data."
            case .unsupportedVersion: return "This clipboard data requires a newer Dust3D editor."
            }
        }
        if let pasteboard = error as? PasteboardError {
            switch pasteboard {
            case .writeFailed: return "The clipboard could not be written. No nodes were removed."
            }
        }
        if let editor = error as? EditorError {
            switch editor {
            case .notLoaded: return "Open a document before editing."
            case .readOnlyNode: return "This node belongs to a locked, hidden or disabled part."
            case .staleReferenceComposition:
                return "The document or locks changed. Reopen the reference image composer."
            case .staleOriginDrag: return "Origin drag cancelled because the document or constraints changed."
            case .unavailableOrigin:
                return
                    "Set a complete supported document origin first. Unlock position axes to initialize an unavailable origin."
            case .invalidPivotSelection: return "Select exactly one node as the rotation pivot."
            case .invalidScale: return "Enter a finite, positive scale factor. Use 1 to keep the current size."
            }
        }
        return error.localizedDescription
    }
}

private actor EditorPreviewService {
    func generate(_ data: Data) throws -> Mesh {
        try Task.checkCancellation()
        let mesh = try MeshLoader.load(data: data)
        try Task.checkCancellation()
        return mesh
    }
}
