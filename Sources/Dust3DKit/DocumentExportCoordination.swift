import Foundation
import os

typealias DocumentExportCancellationCheck = @Sendable () throws -> Void
typealias DocumentCoordinatedOperation = @Sendable (URL, @escaping DocumentExportCancellationCheck) async throws -> Void

protocol DocumentExportCoordinating: Sendable {
    func coordinate(destination: URL, operation: @escaping DocumentCoordinatedOperation) async throws -> URL
}

/// Holds each coordinated accessor open on its own queue while the session serializes publication.
struct NativeDocumentExportCoordinator: DocumentExportCoordinating {
    var onScheduled: @Sendable () -> Void = {}

    func coordinate(destination: URL, operation: @escaping DocumentCoordinatedOperation) async throws -> URL {
        let cancellation = DocumentCoordinationCancellation()
        defer { cancellation.close() }
        return try await withTaskCancellationHandler {
            try cancellation.check()
            let coordinator = NSFileCoordinator(filePresenter: nil)
            cancellation.install(coordinator)
            let intent = NSFileAccessIntent.writingIntent(with: destination, options: .forReplacing)
            let queue = OperationQueue()
            queue.name = "org.dust3d.export-coordination"
            queue.qualityOfService = .userInitiated
            queue.maxConcurrentOperationCount = 1
            let lease: DocumentCoordinationLease = try await withCheckedThrowingContinuation { continuation in
                coordinator.coordinate(with: [intent], queue: queue) { error in
                    if let error {
                        let cause = error as NSError
                        if cause.domain == NSCocoaErrorDomain, cause.code == CocoaError.userCancelled.rawValue,
                            cancellation.isCancelled
                        {
                            continuation.resume(throwing: CancellationError())
                        } else {
                            continuation.resume(throwing: error)
                        }
                        return
                    }
                    let lease = DocumentCoordinationLease(destination: intent.url)
                    continuation.resume(returning: lease)
                    // Hold the accessor on this request's queue until the caller finishes publication.
                    lease.wait()
                }
                cancellation.cancelIfNeeded()
                onScheduled()
            }
            defer { lease.release() }
            try cancellation.check()
            try await operation(lease.destination, cancellation.check)
            return lease.destination
        } onCancel: {
            cancellation.cancel()
        }
    }
}

/// One accessor may be released once; the private coordinator queue owns the wait.
private final class DocumentCoordinationLease: Sendable {
    let destination: URL
    private let semaphore = DispatchSemaphore(value: 0)
    private let released = OSAllocatedUnfairLock(initialState: false)
    init(destination: URL) { self.destination = destination }
    func wait() { semaphore.wait() }
    func release() {
        let shouldSignal = released.withLock { state in
            guard !state else { return false }
            state = true
            return true
        }
        if shouldSignal { semaphore.signal() }
    }
}

/// Only Apple's documented thread-safe cancel() crosses the request's scheduling boundary.
private final class DocumentCoordinationCancellation: Sendable {
    private struct State {
        var isCancelled = false
        var coordinator: NSFileCoordinator?
    }
    private let state = OSAllocatedUnfairLock(uncheckedState: State())
    var isCancelled: Bool { state.withLock { $0.isCancelled } }
    func check() throws { if isCancelled { throw CancellationError() } }
    func install(_ coordinator: NSFileCoordinator) { state.withLockUnchecked { $0.coordinator = coordinator } }
    func cancel() {
        state.withLock {
            $0.isCancelled = true
            $0.coordinator?.cancel()
        }
    }
    func cancelIfNeeded() { state.withLock { if $0.isCancelled { $0.coordinator?.cancel() } } }
    func close() { state.withLock { $0.coordinator = nil } }
}
