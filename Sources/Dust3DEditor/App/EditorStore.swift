import CoreGraphics
import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Dust3DRendering
import Foundation
import Observation
import os

@MainActor @Observable
final class EditorStore {
    private(set) var snapshot: EditorSnapshot?
    private(set) var isWorking = false { didSet { onEditingChanged?(isWorking) } }
    private(set) var previewState = MeshPreviewState<EditorPreviewOutput>()
    var mesh: IndexedMesh? { previewState.value?.mesh }
    var previewSourceHints: MeshSourceHints? {
        guard !previewState.isStale, !isWorking, !stopped else { return nil }
        return previewState.value?.sourceHints
    }
    private(set) var materialState = MeshPreviewState<MeshMaterialContent>()
    var materialContent: MeshMaterialContent? {
        materialRenderError == nil && !materialState.isStale ? materialState.value : nil
    }
    var bakedMesh: MeshWithBakedTextures? {
        guard case .baked(let value) = materialContent else { return nil }
        return value
    }
    var importedMaterials: ImportedMaterialRenderData? {
        guard case .imported(let value) = materialContent else { return nil }
        return value
    }
    var sourceBakedMesh: SourceBakedMesh? {
        guard case .sourceBaked(let value) = materialContent else { return nil }
        return value
    }
    var previewCompatibilityWarning: String? {
        let tree = snapshot?.componentTree
        let legacyDetails = tree.flatMap { tree -> Bool? in
            guard tree.failureDescription == nil else { return nil }
            return tree.rows.contains { $0.component.hasLegacySurfaceDetails }
        }
        return MaterialPreviewWarning.message(
            mesh?.warning ?? "",
            hasBakedMaterials: (bakedMesh != nil || sourceBakedMesh != nil)
                && renderedMaterialRevision == materialViewportRevision,
            hasImportedMaterials: (importedMaterials != nil || sourceBakedMesh != nil)
                && renderedMaterialRevision == materialViewportRevision,
            hasSourceBakedMaterials: sourceBakedMesh != nil
                && renderedMaterialRevision == materialViewportRevision,
            hasLegacySurfaceDetails: legacyDetails)
    }
    private var renderedMaterialRevision: Int?

    func materialsRendered(revision: Int) {
        guard materialContent != nil, revision == materialViewportRevision else { return }
        renderedMaterialRevision = revision
    }

    func materialsFailed(_ cause: String, revision: Int) {
        guard materialContent != nil, revision == materialViewportRevision else { return }
        renderedMaterialRevision = nil
        materialRenderError = cause
    }

    var isBakingMaterials: Bool { materialState.isGenerating }
    var isUpdatingMaterials: Bool {
        isBakingMaterials || (materialContent != nil && renderedMaterialRevision != materialViewportRevision)
    }
    var materialRenderError: String?
    var materialIssue: String? { materialRenderError ?? materialState.errorMessage }
    var previewRevision: Int { previewState.revision }
    var materialViewportRevision: Int { previewState.revision + materialState.revision }
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
    private let exportService: DocumentExportFileService?
    private var exportTask: Task<EditorExportReceipt, any Error>?

    // A retained preview may belong to a previous load; recovery must preserve current-load provenance and errors.
    private struct RecoveryLoadIdentity {
        let documentIdentity: UUID
        let fileIdentity: UUID?
    }
    private var recoveryLoadResult: Result<RecoveryLoadIdentity, any Error>?
    private let materialPreparation: any ArchiveMaterialPreparing
    private(set) var materialGeneration: Task<Void, Never>?
    private let preview: any EditorPreviewServing
    private var previewScopeID = UUID()
    private(set) var previewCacheStatistics: MeshGenerationStatistics?
    private(set) var previewSourceIssue: MeshLoadingError?
    private static let previewLogger = Logger(
        subsystem: RuntimeBuildIdentity.current.loggingSubsystem(fallback: "org.dust3d.editor"),
        category: "PreviewCache")
    private let colorImages: any ColorImageServing
    private(set) var colorImagePreparation: Task<Void, Never>?
    private(set) var isPreparingColorImage = false
    private var colorImageRequestID = UUID()
    private var operationRequestID = UUID()
    private let referenceImages: any ReferenceImageServing
    private var operation: Task<Void, Never>?
    // Lifecycle callers can await a captured request's cooperative completion.
    private(set) var generation: Task<Void, Never>?
    private var referenceGeneration: Task<Void, Never>?
    private var referenceRequestID = UUID()
    private var stopped = false

    init(
        colorImages: any ColorImageServing = ColorImageService(),
        referenceImages: any ReferenceImageServing = ReferenceImageService(),
        preview: any EditorPreviewServing = EditorPreviewService(),
        materialBaker: any ArchiveTextureBaking = ArchiveTextureBakingService(),
        importedMaterialLoader: any ArchiveImportedMaterialLoading = ArchiveImportedMaterialService(),
        sourceMaterialBaker: any ArchiveSourceTextureBaking = ArchiveSourceTextureBakingService(),
        exportService: DocumentExportFileService? = nil
    ) {
        self.exportService = exportService
        self.colorImages = colorImages
        self.referenceImages = referenceImages
        self.preview = preview
        materialPreparation = ArchiveMaterialPreparationService(
            importedLoader: importedMaterialLoader, proceduralBaker: materialBaker, sourceBaker: sourceMaterialBaker)
    }

    var locks: Set<EditingConstraint> { snapshot?.locks ?? [] }
    var canSave: Bool { snapshot != nil && !isWorking && !stopped }
    var canEditRigSettings: Bool { canSave }

    var canExport: Bool {
        guard exportService != nil, canSave,
            case .success(let accepted) = recoveryLoadResult,
            snapshot?.documentIdentity == accepted.documentIdentity
        else { return false }
        return true
    }

    /// Export one accepted snapshot without changing save state, history, preview or source bytes.
    /// Production scene commands must inject a reviewed native encoder and supply their source URL.
    func exportDocument(format: DocumentExportFormat, to destination: URL, sourceURL: URL?) async throws
        -> EditorExportReceipt
    {
        try Task.checkCancellation()
        guard let exportService else { throw EditorExportWorkflowError.unavailable }
        guard !isWorking, !stopped, let recoveryLoadResult else { throw EditorExportWorkflowError.notReady }
        let accepted = try recoveryLoadResult.get()
        guard let snapshot, snapshot.documentIdentity == accepted.documentIdentity else {
            throw EditorExportWorkflowError.notReady
        }
        let target = EditorExportTarget(snapshot: snapshot)
        cancelColorImagePreparation()
        cancelOriginDrag()
        let requestID = UUID()
        operationRequestID = requestID
        isWorking = true
        let task = Task { [session] in
            let output = try await exportService.export(
                snapshot.document, format: format, to: destination, sourceURL: sourceURL,
                validateSnapshot: { try await session.validateExport(target) },
                publish: { commit in try await session.publishExport(target, publication: commit) })
            return EditorExportReceipt(
                documentIdentity: snapshot.documentIdentity, documentRevision: snapshot.documentRevision,
                destination: destination, format: format, byteCount: output.bytes.count, warning: output.warning)
        }
        exportTask = task
        defer {
            if operationRequestID == requestID {
                exportTask = nil
                isWorking = false
            }
        }
        do {
            let receipt = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            if operationRequestID == requestID { errorMessage = nil }
            return receipt
        } catch {
            if operationRequestID == requestID, !stopped, !(error is CancellationError) {
                errorMessage = Self.message(error)
            }
            throw error
        }
    }

    private func cancelExport() {
        exportTask?.cancel()
        exportTask = nil
    }

    func setRigType(_ type: DocumentRigType) {
        guard canEditRigSettings else { return }
        perform(changesRendering: false) { try await $0.apply([.setRigType(type)]) }
    }

    func setHeadHasEyelids(_ enabled: Bool) {
        guard canEditRigSettings else { return }
        perform(changesRendering: false) { try await $0.apply([.setHeadHasEyelids(enabled)]) }
    }

    func recoverySnapshot(documentID: UUID) throws -> EditorRecoverySnapshot {
        guard !stopped else { throw EditorRecoveryCopyError.stopped }
        guard !isWorking else { throw EditorRecoveryCopyError.editInProgress }
        guard let recoveryLoadResult else { throw EditorRecoveryCopyError.notLoaded }
        let accepted = try recoveryLoadResult.get()
        if let fileIdentity = accepted.fileIdentity, fileIdentity != documentID {
            throw EditorRecoveryCopyError.identityMismatch
        }
        guard let snapshot, snapshot.documentIdentity == accepted.documentIdentity else {
            throw EditorRecoveryCopyError.notLoaded
        }
        return .init(documentID: documentID, revision: snapshot.documentRevision, document: snapshot.document)
    }
    var canUndo: Bool { !isWorking && snapshot?.canUndo == true }
    var canRedo: Bool { !isWorking && snapshot?.canRedo == true }

    /// Scene callers supply their FileDocument identity so recovery cannot relabel retained preview state.
    func load(data: Data, fileIdentity: UUID? = nil) async {
        cancelExport()
        cancelColorImagePreparation()
        operation?.cancel()
        let requestID = UUID()
        operationRequestID = requestID
        cancelOriginDrag()
        stopped = false
        isWorking = true
        recoveryLoadResult = nil
        defer { if operationRequestID == requestID { isWorking = false } }
        do {
            let next = try await session.open(data: data)
            guard !Task.isCancelled, !stopped, operationRequestID == requestID else { return }
            snapshot = next
            recoveryLoadResult = .success(.init(documentIdentity: next.documentIdentity, fileIdentity: fileIdentity))
            referenceImage = nil
            fit()
            clearPreview()
            generate(next)
            refreshReferenceImage(next, forceFit: true)
        } catch {
            if !Task.isCancelled, operationRequestID == requestID {
                recoveryLoadResult = .failure(error)
                errorMessage = Self.message(error)
            }
        }
    }

    func cancelColorImagePreparation() {
        colorImageRequestID = UUID()
        colorImagePreparation?.cancel()
        colorImagePreparation = nil
        isPreparingColorImage = false
    }

    private enum PreparedColorImage: Sendable {
        case imported(Data)
        case retained(String)
    }

    func importComponentColorImage(url: URL, target: ComponentColorImageTarget) {
        prepareComponentColorImage(target: target) { [colorImages] in
            .imported(try await colorImages.importImage(url: url))
        }
    }

    func assignComponentColorImage(_ asset: DocumentColorImageAsset, target: ComponentColorImageTarget) {
        guard let snapshot, target.isCurrent(in: snapshot), let imageID = asset.imageID else { return }
        let document = snapshot.document
        prepareComponentColorImage(target: target) { [colorImages] in
            try await colorImages.validateRetainedImage(document: document, asset: asset)
            return .retained(imageID)
        }
    }

    func clearComponentColorImage(target: ComponentColorImageTarget) {
        perform(regenerateMesh: false) { try await $0.setComponentColorImage(imageID: nil, target: target) }
    }

    private func prepareComponentColorImage(
        target: ComponentColorImageTarget,
        prepare: @escaping @Sendable () async throws -> PreparedColorImage
    ) {
        guard !isWorking, !stopped, let snapshot, target.isCurrent(in: snapshot) else { return }
        cancelColorImagePreparation()
        let requestID = colorImageRequestID
        isPreparingColorImage = true
        errorMessage = nil
        colorImagePreparation = Task {
            defer {
                if colorImageRequestID == requestID {
                    isPreparingColorImage = false
                    colorImagePreparation = nil
                }
            }
            do {
                let prepared = try await prepare()
                guard !Task.isCancelled, !stopped, colorImageRequestID == requestID,
                    let current = self.snapshot, target.isCurrent(in: current)
                else { return }
                // End preparation before perform invalidates pending image requests.
                isPreparingColorImage = false
                colorImagePreparation = nil
                perform(regenerateMesh: false) { session in
                    switch prepared {
                    case .imported(let png): try await session.importComponentColorImage(png: png, target: target)
                    case .retained(let imageID):
                        try await session.setComponentColorImage(imageID: imageID, target: target)
                    }
                }
            } catch {
                if !Task.isCancelled, !stopped, colorImageRequestID == requestID {
                    errorMessage = Self.message(error)
                }
            }
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
    func selectComponent(_ id: String?) { perform(commits: false) { try await $0.selectComponent(id) } }
    func selectComponents(_ ids: Set<String>) { perform(commits: false) { try await $0.selectComponents(ids) } }
    func selectOnlyComponent(_ id: String) {
        guard snapshot?.selectedComponentIDs.contains(id) == true else { return }
        selectComponent(id)
    }
    func clearComponentSelection() { selectComponents([]) }
    var canGroupComponents: Bool { !isWorking && !stopped && snapshot?.canGroupComponents == true }
    var canUngroupComponent: Bool { !isWorking && !stopped && snapshot?.canUngroupComponent == true }
    func groupSelectedComponents() {
        guard canGroupComponents, let ids = snapshot?.selectedComponentIDs else { return }
        perform { try await $0.groupComponents(ids) }
    }
    func ungroupSelectedComponent() {
        guard canUngroupComponent, let id = snapshot?.selectedComponentID else { return }
        perform { try await $0.apply([.ungroupComponent(id: id)]) }
    }
    func reparentComponent(
        to parent: ComponentParent, target: ComponentReparentTarget,
        completion: (@MainActor (Bool) -> Void)? = nil
    ) {
        perform(completion: completion) { try await $0.reparentComponent(to: parent, target: target) }
    }
    func canReorderComponent(_ direction: ComponentOrderMove) -> Bool {
        !isWorking && !stopped && snapshot?.availableComponentOrderMoves.contains(direction) == true
    }
    func reorderComponent(_ direction: ComponentOrderMove) {
        guard canReorderComponent(direction), let id = snapshot?.selectedComponentID else { return }
        perform { try await $0.apply([.reorderComponent(id: id, direction: direction)]) }
    }
    func setComponentWrapMode(_ id: String, mode: ComponentWrapMode) {
        perform { try await $0.apply([.setComponentWrapMode(id: id, mode: mode)]) }
    }
    func setComponentWrapKeepChildren(_ id: String, value: Bool) {
        perform { try await $0.apply([.setComponentWrapKeepChildren(id: id, value: value)]) }
    }
    func setComponentWrapScalar(_ id: String, property: ComponentWrappingScalarProperty, value: String) {
        guard !isWorking, !stopped else { return }
        guard let number = EngineScalar.parse(value, in: property.bounds) else {
            errorMessage = Self.message(DocumentError.invalidComponentWrapping)
            return
        }
        perform { try await $0.apply([.setComponentWrapScalar(id: id, property: property, value: number)]) }
    }
    func setComponentWrapFaces(_ id: String, faces: String) {
        guard !isWorking, !stopped else { return }
        guard let number = Int(faces), (64...20000).contains(number) else {
            errorMessage = Self.message(DocumentError.invalidComponentWrapping)
            return
        }
        perform { try await $0.apply([.setComponentWrapFaces(id: id, faces: number)]) }
    }
    func setComponentStitchingClosure(_ id: String, property: ComponentStitchingClosureProperty, value: Bool) {
        perform { try await $0.apply([.setComponentStitchingClosure(id: id, property: property, value: value)]) }
    }
    func setComponentStitchingScalar(_ id: String, property: ComponentStitchingScalarProperty, value: String) {
        guard !isWorking, !stopped else { return }
        guard let number = EngineScalar.parse(value, in: property.bounds) else {
            errorMessage = Self.message(DocumentError.invalidComponentStitchingScalar)
            return
        }
        perform { try await $0.apply([.setComponentStitchingScalar(id: id, property: property, value: number)]) }
    }
    func setComponentTargetSegments(_ id: String, segments: String) {
        guard !isWorking, !stopped else { return }
        guard let number = Int(segments), (0...100).contains(number) else {
            errorMessage = Self.message(DocumentError.invalidComponentTargetSegments)
            return
        }
        perform { try await $0.apply([.setComponentTargetSegments(id: id, segments: number)]) }
    }
    func setPartFillLoopInterior(_ id: String, value: Bool) {
        perform { try await $0.apply([.setPartFillLoopInterior(id: id, value: value)]) }
    }
    func setPartTarget(_ id: String, target: PartTarget) {
        perform { try await $0.apply([.setPartTarget(id: id, target: target)]) }
    }
    func setPartCutFace(_ id: String, selection: CutFaceSelection) {
        perform { try await $0.apply([.setPartCutFace(id: id, selection: selection)]) }
    }
    func setPartCutRotation(_ id: String, rotation: String) {
        guard !isWorking, !stopped else { return }
        guard let value = EngineScalar.parse(rotation, in: -1...1) else {
            errorMessage = Self.message(DocumentError.invalidPartCutRotation)
            return
        }
        perform { try await $0.apply([.setPartCutRotation(id: id, rotation: value)]) }
    }
    func setPartMaterial(_ id: String, property: PartMaterialProperty, value: String) {
        guard !isWorking, !stopped else { return }
        guard let scalar = EngineScalar.parse(value, in: property.bounds) else {
            errorMessage = "Enter a value from 0 to \(Int(property.bounds.upperBound)) that the material can represent."
            return
        }
        perform(regenerateMesh: false) {
            try await $0.apply([.setPartMaterial(id: id, property: property, value: scalar)])
        }
    }
    func setPartDeformationScale(_ id: String, property: PartDeformationProperty, value: String) {
        guard !isWorking, !stopped else { return }
        guard let scale = EngineScalar.parse(value, in: 0...2) else {
            errorMessage = Self.message(DocumentError.invalidPartDeformation)
            return
        }
        perform { try await $0.apply([.setPartDeformationScale(id: id, property: property, value: scale)]) }
    }
    func setPartDeformationUnified(_ id: String, value: Bool) {
        perform { try await $0.apply([.setPartDeformationUnified(id: id, value: value)]) }
    }
    func setPartModifier(_ id: String, property: PartModifierProperty, value: Bool) {
        perform { try await $0.apply([.setPartModifier(id: id, property: property, value: value)]) }
    }
    func setEdgeBoneName(_ id: String, name: String) {
        perform(changesRendering: false) { try await $0.apply([.setEdgeBoneName(id: id, name: name)]) }
    }
    func setComponentColor(_ id: String, value: String) {
        guard !isWorking, !stopped else { return }
        guard let color = DocumentColor(archiveValue: value) else {
            errorMessage = Self.message(DocumentError.invalidComponentColor)
            return
        }
        perform { try await $0.apply([.setComponentColor(id: id, color: color)]) }
    }
    func removeComponentColor(_ id: String) {
        perform { try await $0.apply([.setComponentColor(id: id, color: nil)]) }
    }
    func setComponentSmoothCutoff(_ id: String, degrees: String) {
        guard !isWorking, !stopped else { return }
        guard let value = Double(degrees), value.isFinite, (0...180).contains(value) else {
            errorMessage = Self.message(DocumentError.invalidComponentSmoothing)
            return
        }
        perform { try await $0.apply([.setComponentSmoothCutoffDegrees(id: id, degrees: value)]) }
    }
    func setComponentCombineMode(_ id: String, mode: ComponentCombineMode) {
        perform { try await $0.apply([.setComponentCombineMode(id: id, mode: mode)]) }
    }
    func renameComponent(_ id: String, name: String) {
        perform(regenerateMesh: false) { try await $0.apply([.setComponentName(id: id, name: name)]) }
    }
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
        cancelColorImagePreparation()
        cancelOriginDrag()
        let requestID = UUID()
        operationRequestID = requestID
        isWorking = true
        operation = Task {
            defer { if operationRequestID == requestID { isWorking = false } }
            do {
                let data = try await session.copyRepresentations(identifier: UUID().uuidString, onlyEditable: cut)
                guard !Task.isCancelled, !stopped, operationRequestID == requestID else { return }
                try pasteboard.write(data.native, snapshotXML: data.snapshotXML)
                if cut {
                    let next = try await session.deleteSelection()
                    guard !Task.isCancelled, !stopped, operationRequestID == requestID else { return }
                    snapshot = next
                    fit()
                    onDocumentChanged?(next.document.encoded())
                    generate(next)
                }
                errorMessage = nil
            } catch {
                if !Task.isCancelled, operationRequestID == requestID { errorMessage = Self.message(error) }
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
        cancelExport()
        cancelColorImagePreparation()
        operationRequestID = UUID()
        isWorking = false
        cancelOriginDrag()
        stopped = true
        operation?.cancel()
        generation?.cancel()
        referenceGeneration?.cancel()
        clearPreview()
        onDocumentChanged = nil
        onEditingChanged?(false)
        onEditingChanged = nil
    }

    private func perform(
        commits: Bool = true, reloadReferenceImage: Bool = false, regenerateMesh: Bool = true,
        changesRendering: Bool = true,
        completion: (@MainActor (Bool) -> Void)? = nil,
        _ action: @escaping @Sendable (EditorSession) async throws -> EditorSnapshot
    ) {
        guard !isWorking, !stopped else {
            completion?(false)
            return
        }
        cancelColorImagePreparation()
        cancelOriginDrag()
        let requestID = UUID()
        operationRequestID = requestID
        isWorking = true
        operation = Task {
            var succeeded = false
            defer {
                if operationRequestID == requestID { isWorking = false }
                completion?(succeeded)
            }
            do {
                let next = try await action(session)
                guard !Task.isCancelled, !stopped, operationRequestID == requestID else { return }
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
                    if changesRendering {
                        if regenerateMesh {
                            generate(next)
                        } else {
                            clearMaterials()
                            if !previewState.isStale, mesh != nil { generateMaterials(next) }
                        }
                    }
                    if reloadReferenceImage { refreshReferenceImage(next) }
                }
                succeeded = true
            } catch {
                if !Task.isCancelled, operationRequestID == requestID { errorMessage = Self.message(error) }
            }
        }
    }

    private func clearPreview() {
        clearMaterials()
        generation?.cancel()
        previewState.clear()
        previewCacheStatistics = nil
        previewSourceIssue = nil
        let previousScope = previewScopeID
        previewScopeID = UUID()
        Task { [preview] in
            do {
                try await preview.reset(scopeID: previousScope)
            } catch {
                Self.previewLogger.error(
                    "Preview cache reset for \(previousScope.uuidString, privacy: .public) failed: \(error.localizedDescription, privacy: .private)"
                )
            }
        }
    }

    private func generate(_ snapshot: EditorSnapshot) {
        clearMaterials()
        generation?.cancel()
        renderError = nil
        guard snapshot.hasEnabledGeometry else {
            clearPreview()
            return
        }
        previewCacheStatistics = nil
        previewSourceIssue = nil
        let scopeID = previewScopeID
        let requestID = UUID()
        previewState.begin(requestID: requestID)
        generation = Task {
            do {
                try await Task.sleep(for: .milliseconds(150))
                let result = try await preview.generate(snapshot.document.encoded(), scopeID: scopeID)
                // Asset-only edits can advance document revision without changing geometry; request identity wins.
                guard !Task.isCancelled, !stopped, scopeID == previewScopeID else {
                    return
                }
                previewCacheStatistics = result.statistics
                previewSourceIssue = result.sourceIssue
                if let output = result.output {
                    previewState.succeed(output, requestID: requestID)
                    if let currentSnapshot = self.snapshot { generateMaterials(currentSnapshot) }
                } else {
                    previewState.succeedEmpty(requestID: requestID)
                }
            } catch {
                guard !Task.isCancelled, !stopped, scopeID == previewScopeID else { return }
                previewState.fail(Self.message(error), requestID: requestID)
            }
        }
    }

    private func clearMaterials() {
        renderedMaterialRevision = nil
        materialGeneration?.cancel()
        materialState.clear()
        materialRenderError = nil
    }

    func retryMaterials() {
        guard !stopped, !isWorking, !previewState.isGenerating, !previewState.isStale,
            mesh != nil, let snapshot
        else { return }
        generateMaterials(snapshot)
    }

    private func generateMaterials(_ snapshot: EditorSnapshot) {
        renderedMaterialRevision = nil
        materialGeneration?.cancel()
        materialRenderError = nil
        let requestID = UUID()
        let scopeID = previewScopeID
        materialState.begin(requestID: requestID)
        materialGeneration = Task { [materialPreparation] in
            do {
                let data = snapshot.document.encoded()
                let result = try await materialPreparation.load(data: data, options: .init())
                guard !Task.isCancelled, !stopped, scopeID == previewScopeID else { return }
                materialState.succeed(result, requestID: requestID)
            } catch {
                guard !Task.isCancelled, !stopped, scopeID == previewScopeID else { return }
                materialState.fail(error.localizedDescription, requestID: requestID)
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
            case .invalidComponent:
                return "The document contains unsupported component tags or ambiguous identities/containers."
            case .invalidComponentStructure:
                return "Choose unique sibling components and an unlinked group destination without creating a cycle."
            case .invalidComponentWrapping:
                return "Choose a group and wrapping values within the supported editing ranges."
            case .invalidComponentTargetSegments: return "Enter a whole target segment count from 0 to 100."
            case .invalidComponentStitchingScalar:
                return "Enter a depth from 0 to 2 or sharpness from 0 to 1 that the modeling engine can represent."
            case .invalidComponentSmoothing: return "Enter a finite smoothing cutoff from 0 to 180 degrees."
            case .invalidComponentColor: return "Enter #RRGGBB or #AARRGGBB, with alpha first."
            case .invalidComponentName: return "Use a single-line component name of at most 1024 UTF-8 bytes."
            case .missingComponent(let id): return "Component \(id) is not present in this document."
            case .invalidPartCutFace:
                return "Choose a preset or an existing profile part with an engine-compatible identity."
            case .invalidPartCutRotation:
                return "Enter a cut rotation from -1 to 1 that the modeling engine can represent."
            case .invalidPartMaterial: return "Enter a material value within its supported range."
            case .invalidPartDeformation: return "Enter a scale from 0 to 2 that the modeling engine can represent."
            case .invalidPartName: return "Use a single-line part name of at most 1024 UTF-8 bytes."
            case .invalidBoneName:
                return "Use an exact bone name of at most 1024 UTF-8 bytes without controls or newlines."
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
            case .staleColorImageTarget: return "The document or selected component changed. Choose the image again."
            case .staleComponentMove: return "The document or component selection changed. Reset the parent chooser."
            case .staleOriginDrag: return "Origin drag cancelled because the document or constraints changed."
            case .staleExport:
                return "Export cancelled because the document changed. Export the current document again."
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
