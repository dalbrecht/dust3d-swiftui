import Dust3DDocument
import Dust3DKit
import Dust3DRendering
import Foundation
import OSLog
import Observation

/// Host availability is separate from original native/copy errors.
enum EditorAnimationCatalogError: LocalizedError, Equatable {
    case unavailable
    var errorDescription: String? { "Animation type definitions are unavailable in this session." }
}

/// Optional scene-owned definitions never set the editor's primary working/Save barrier.
@MainActor @Observable
final class EditorAnimationCatalogState {
    private let service: (any AnimationCatalogLoading)?
    private var stopped = false
    private(set) var catalog: AnimationAuthoringCatalog?
    private(set) var issue: (any Error)?
    private(set) var isLoading = false
    private(set) var task: Task<Void, Never>?
    private static let logger = Logger(
        subsystem: RuntimeBuildIdentity.current.loggingSubsystem(fallback: "org.dust3d.editor"),
        category: "AnimationCatalog")

    init(service: (any AnimationCatalogLoading)?) { self.service = service }

    var canLoad: Bool { !stopped && service != nil && task == nil && catalog == nil }

    /// Own one query until its actual cooperative completion; cache fixed definitions after success.
    @discardableResult
    func load() -> Task<Void, Never>? {
        guard !stopped else { return nil }
        if let task { return task }
        guard catalog == nil else { return nil }
        guard let service else {
            issue = EditorAnimationCatalogError.unavailable
            return nil
        }
        issue = nil
        isLoading = true
        let requestID = UUID().uuidString
        Self.logger.info("operation=loadAnimationCatalog requestID=\(requestID, privacy: .public) started")
        let operation = Task { [weak self, service] in
            defer {
                self?.isLoading = false
                self?.task = nil
            }
            do {
                try Task.checkCancellation()
                guard self?.stopped == false else { return }
                let value = try await service.load()
                try Task.checkCancellation()
                guard let self, !stopped else { return }
                catalog = value
                Self.logger.info(
                    "operation=loadAnimationCatalog requestID=\(requestID, privacy: .public) clips=\(value.clips.count)"
                )
            } catch {
                guard let self, !stopped, !(error is CancellationError) else { return }
                issue = error
                Self.logger.error(
                    "operation=loadAnimationCatalog requestID=\(requestID, privacy: .public) cause=\(String(describing: error), privacy: .private)"
                )
            }
        }
        task = operation
        return operation
    }

    func stop() {
        stopped = true
        catalog = nil
        issue = nil
        task?.cancel()
    }
}
