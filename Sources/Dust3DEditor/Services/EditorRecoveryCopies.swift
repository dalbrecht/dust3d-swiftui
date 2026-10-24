import Dust3DDocument
import Dust3DEditorModel
import Foundation

enum EditorRecoveryCopyError: Error, Sendable, Equatable {
    case alreadyWriting, notLoaded, editInProgress, stopped, identityMismatch, unsafeLocation, unsafeIdentity
}

struct EditorRecoverySnapshot: Sendable {
    let request: RecoveryCopyRequest
    let document: Dust3DDocument

    init(documentID: UUID, revision: Int, document: Dust3DDocument) {
        request = .init(documentID: documentID, revision: revision, byteCount: document.encoded().count)
        self.document = document
    }
}

struct EditorRecoveryFailure: Sendable {
    let documentID: UUID?
    let cause: any Error
}

enum EditorRecoveryCapture: Sendable {
    case snapshot(EditorRecoverySnapshot)
    case failure(EditorRecoveryFailure)
}

struct EditorRecoveryReport: Sendable {
    let requestID: UUID
    let requestedCount: Int
    var copied: [RecoveryCopyRequest] = []
    var failures: [EditorRecoveryFailure] = []
    var receiptError: (any Error)?
}

protocol EditorRecoveryCopyWriting: Sendable {
    func write(captures: [EditorRecoveryCapture], requestID: UUID) async throws -> EditorRecoveryReport
}

enum EditorRecoveryCopyChannel {
    static let notification = Notification.Name("org.dust3d.editor.write-recovery-copies")
}

/// Weak window handlers capture accepted values on the editing actor, without changing savepoints or selection.
@MainActor final class EditorRecoveryCopyRegistry {
    static let shared = EditorRecoveryCopyRegistry(
        writer: EditorRecoveryCopyFileService(bundleIdentifier: Bundle.main.bundleIdentifier))
    private var captures: [UUID: @MainActor () throws -> EditorRecoverySnapshot] = [:]
    private let writer: any EditorRecoveryCopyWriting
    private var isWriting = false

    init(writer: any EditorRecoveryCopyWriting) { self.writer = writer }

    func register(_ identifier: UUID, capture: @escaping @MainActor () throws -> EditorRecoverySnapshot) {
        captures[identifier] = capture
    }

    func unregister(_ identifier: UUID) { captures.removeValue(forKey: identifier) }

    func recover(requestID: UUID) async throws -> EditorRecoveryReport {
        guard !isWriting else { throw EditorRecoveryCopyError.alreadyWriting }
        guard captures.count <= RecoveryCopyPlan.maximumDocuments else { throw RecoveryCopyPlanError.tooManyDocuments }
        isWriting = true
        defer { isWriting = false }
        let snapshots = captures.sorted { $0.key.uuidString < $1.key.uuidString }.map { identifier, capture in
            do {
                let snapshot = try capture()
                guard snapshot.request.documentID == identifier else { throw EditorRecoveryCopyError.identityMismatch }
                return EditorRecoveryCapture.snapshot(snapshot)
            } catch {
                return .failure(.init(documentID: identifier, cause: error))
            }
        }
        return try await writer.write(captures: snapshots, requestID: requestID)
    }
}
