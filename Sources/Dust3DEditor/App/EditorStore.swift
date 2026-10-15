import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import Observation

@MainActor @Observable
final class EditorStore {
    private(set) var snapshot: EditorSnapshot?
    private(set) var isWorking = false
    private(set) var mesh: Mesh?
    private(set) var previewRevision = 0
    private(set) var isGenerating = false
    var errorMessage: String?
    var previewError: String?
    var bounds = CanvasBounds(nodes: [])
    var plane = EditingPlane.front
    var isWireframe = false
    var cameraReset = 0
    var onDocumentChanged: ((Data) -> Void)?
    private let session = EditorSession()
    private let preview = EditorPreviewService()
    private var operation: Task<Void, Never>?
    private var generation: Task<Void, Never>?
    private var stopped = false

    var locks: Set<EditingConstraint> { snapshot?.locks ?? [] }
    var canUndo: Bool { !isWorking && snapshot?.canUndo == true }
    var canRedo: Bool { !isWorking && snapshot?.canRedo == true }

    func load(data: Data) async {
        stopped = false
        isWorking = true
        defer { isWorking = false }
        do {
            let next = try await session.open(data: data)
            guard !Task.isCancelled, !stopped else { return }
            snapshot = next
            fit()
            generate(next)
        } catch {
            if !Task.isCancelled { errorMessage = Self.message(error) }
        }
    }

    func setLock(_ constraint: EditingConstraint, isLocked: Bool) {
        perform(commits: false) { try await $0.setLock(constraint, isLocked: isLocked) }
    }

    func select(_ id: String?) { perform(commits: false) { try await $0.select(id) } }

    func select(_ ids: Set<String>) { perform(commits: false) { try await $0.select(ids) } }
    func toggleSelection(_ id: String) { perform(commits: false) { try await $0.toggleSelection(id) } }
    func selectAll() { perform(commits: false) { try await $0.selectAll() } }
    func move(id: String, to position: NodePosition) { perform { try await $0.move(id: id, to: position) } }
    func moveSelection(by delta: NodePosition) { perform { try await $0.moveSelection(by: delta) } }
    func scaleSelection(positionFactor: Double, radiusFactor: Double) {
        perform { try await $0.scaleSelection(positionFactor: positionFactor, radiusFactor: radiusFactor) }
    }
    var canTransform: Bool { !isWorking && snapshot?.selectedNodes.contains(where: \.isEditable) == true }
    func transformSelection(_ transform: SelectionTransform) { perform { try await $0.transformSelection(transform) } }
    func reverseSelectedEdges() { perform { try await $0.reverseSelectedEdges() } }
    func reverseEdge(_ id: String) { perform { try await $0.apply([.reverseEdges([id])]) } }

    var canCopyNodes: Bool { !isWorking && snapshot?.canCopyNodes == true }
    var canCutNodes: Bool { !isWorking && snapshot?.canCutNodes == true }

    /// Clipboard write completes before a Cut can mutate the document.
    func copyNodes(cut: Bool = false, to pasteboard: EditorPasteboard) {
        guard cut ? canCutNodes : canCopyNodes, !stopped else { return }
        isWorking = true
        operation = Task {
            defer { isWorking = false }
            do {
                let data = try await session.copyPayload(identifier: UUID().uuidString, onlyEditable: cut)
                guard !Task.isCancelled, !stopped else { return }
                try pasteboard.write(data)
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

    func pasteNodes(from pasteboard: EditorPasteboard) {
        guard !isWorking, !stopped, snapshot != nil else { return }
        do {
            let data = try pasteboard.read()
            perform { try await $0.paste(data: data) }
        } catch { errorMessage = Self.message(error) }
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

    func undo() { perform { try await $0.undo() } }
    func redo() { perform { try await $0.redo() } }

    func fit() {
        bounds = CanvasBounds(nodes: snapshot?.nodes ?? [])
        cameraReset += 1
    }

    func stop() {
        stopped = true
        operation?.cancel()
        generation?.cancel()
        onDocumentChanged = nil
    }

    private func perform(
        commits: Bool = true, _ action: @escaping @Sendable (EditorSession) async throws -> EditorSnapshot
    ) {
        guard !isWorking, !stopped else { return }
        isWorking = true
        operation = Task {
            defer { isWorking = false }
            do {
                let next = try await action(session)
                guard !Task.isCancelled, !stopped else { return }
                let changed = next.documentRevision != snapshot?.documentRevision
                let countChanged = next.nodes.count != snapshot?.nodes.count
                snapshot = next
                if countChanged { fit() }
                errorMessage = nil
                if commits && changed {
                    onDocumentChanged?(next.document.encoded())
                    generate(next)
                }
            } catch {
                if !Task.isCancelled { errorMessage = Self.message(error) }
            }
        }
    }

    private func generate(_ snapshot: EditorSnapshot) {
        generation?.cancel()
        previewError = nil
        guard !snapshot.nodes.isEmpty else {
            mesh = nil
            isGenerating = false
            return
        }
        isGenerating = true
        generation = Task {
            do {
                try await Task.sleep(for: .milliseconds(150))
                let result = try await preview.generate(snapshot.document.encoded())
                guard !Task.isCancelled, !stopped, self.snapshot?.documentRevision == snapshot.documentRevision else {
                    return
                }
                mesh = result
                previewRevision += 1
                isGenerating = false
            } catch {
                guard !Task.isCancelled, !stopped else { return }
                mesh = nil
                previewError = Self.message(error)
                isGenerating = false
            }
        }
    }

    static func message(_ error: Error) -> String {
        if let document = error as? DocumentError {
            switch document {
            case .invalidArchive: return "This file is not a supported Dust3D 1.0 archive."
            case .invalidXML: return "The document contains invalid or unsupported XML."
            case .limitExceeded: return "The document or edit exceeds supported size or undo-history limits."
            case .missingNode(let id): return "Node \(id) is not present in this document."
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
            case .noNodes: return "The clipboard does not contain Dust3D nodes."
            case .writeFailed: return "The clipboard could not be written. No nodes were removed."
            }
        }
        if let editor = error as? EditorError {
            switch editor {
            case .notLoaded: return "Open a document before editing."
            case .readOnlyNode: return "This node belongs to a locked or hidden part."
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
