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
    func deleteSelection() { perform { try await $0.deleteSelection() } }

    func edit(id: String, position: NodePosition, radius: Double) {
        perform { try await $0.edit(id: id, position: position, radius: radius) }
    }

    func addNode(newPart: Bool = false) {
        let selected = newPart ? nil : snapshot?.selectedNode
        let nodeID = Self.identifier()
        let partID = selected?.partID ?? Self.identifier()
        let position =
            selected.map { NodePosition(x: $0.value.position.x, y: $0.value.position.y + 0.25, z: $0.value.position.z) }
            ?? NodePosition(x: 0.5, y: 0.5, z: 0.5)
        var commands: [DocumentCommand] = [
            .addNode(
                id: nodeID, partID: partID, componentID: selected?.partID == nil ? Self.identifier() : nil,
                position: position, radius: selected?.value.radius ?? 0.1)
        ]
        if let selected, selected.partID != nil {
            commands.append(.addEdge(id: Self.identifier(), from: selected.id, to: nodeID))
        }
        let transaction = commands
        perform { try await $0.apply(transaction, selecting: nodeID) }
    }

    func connect(to id: String) {
        guard let selected = snapshot?.selectedID else { return }
        let command = DocumentCommand.addEdge(id: Self.identifier(), from: selected, to: id)
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
            case .transactionAlreadyOpen: return "An edit transaction is already in progress."
            case .noTransaction: return "No edit transaction is in progress."
            }
        }
        if let editor = error as? EditorError {
            switch editor {
            case .notLoaded: return "Open a document before editing."
            case .readOnlyNode: return "This node belongs to a locked or hidden part."
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
