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

    func select(_ id: String?) { perform(commits: false) { try await $0.select(id) } }

    func edit(id: String, position: NodePosition, radius: Double) {
        perform { try await $0.edit(id: id, position: position, radius: radius) }
    }

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
                snapshot = next
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
