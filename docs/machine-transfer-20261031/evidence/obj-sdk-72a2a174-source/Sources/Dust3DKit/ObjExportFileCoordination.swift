import Foundation
import os

typealias ObjExportCancellationCheck = @Sendable () throws -> Void
typealias ObjExportCoordinatedWrite = @Sendable (URL, ObjExportCancellationCheck) throws -> ObjExportWriteReceipt

protocol ObjExportFileCoordinating: Sendable {
    func coordinate(destination: URL, operation: @escaping ObjExportCoordinatedWrite) async throws
        -> ObjExportWriteReceipt
}

/// Each request owns its coordinator; presenter waits do not occupy the writer actor.
struct NativeObjExportFileCoordination: ObjExportFileCoordinating {
    func coordinate(destination: URL, operation: @escaping ObjExportCoordinatedWrite) async throws
        -> ObjExportWriteReceipt
    {
        let cancellation = ObjExportCoordinationCancellation()
        defer { cancellation.close() }
        return try await withTaskCancellationHandler {
            try cancellation.check()
            let coordinator = NSFileCoordinator(filePresenter: nil)
            cancellation.install(coordinator)
            let intent = NSFileAccessIntent.writingIntent(with: destination, options: .forReplacing)
            let queue = OperationQueue()
            queue.name = "org.dust3d.obj-export-access"
            queue.qualityOfService = .userInitiated
            queue.maxConcurrentOperationCount = 1
            return try await withCheckedThrowingContinuation { continuation in
                coordinator.coordinate(with: [intent], queue: queue) { error in
                    let result = Result {
                        if let error {
                            let cause = error as NSError
                            if cause.domain == NSCocoaErrorDomain, cause.code == CocoaError.userCancelled.rawValue,
                                cancellation.isCancelled
                            {
                                throw CancellationError()
                            }
                            throw error
                        }
                        try cancellation.check()
                        return try operation(intent.url, cancellation.check)
                    }
                    continuation.resume(with: result)
                }
                // Cancellation may precede scheduling, when cancel() has no active request to stop.
                cancellation.cancelIfNeeded()
            }
        } onCancel: {
            cancellation.cancel()
        }
    }
}

/// Only cancel() crosses threads; all other coordinator methods stay at their creation/scheduling site.
/// Apple's contract explicitly permits cancel() from any thread and says it returns immediately.
final class ObjExportCoordinationCancellation: Sendable {
    private struct State {
        var isCancelled = false
        var coordinator: NSFileCoordinator?
    }
    private let state = OSAllocatedUnfairLock(uncheckedState: State())

    var isCancelled: Bool { state.withLock { $0.isCancelled } }
    func check() throws {
        if isCancelled { throw CancellationError() }
    }
    func install(_ coordinator: NSFileCoordinator) {
        // The non-Sendable object stays owned by this request. Only documented thread-safe cancel()
        // is invoked from the cancellation handler; installation does not expose the object.
        state.withLockUnchecked { $0.coordinator = coordinator }
    }
    func cancel() {
        state.withLock {
            $0.isCancelled = true
            $0.coordinator?.cancel()
        }
    }
    func cancelIfNeeded() {
        state.withLock { if $0.isCancelled { $0.coordinator?.cancel() } }
    }
    func close() { state.withLock { $0.coordinator = nil } }
}
