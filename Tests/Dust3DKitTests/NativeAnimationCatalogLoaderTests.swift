import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DKit

private enum CatalogCopyFixtureError: Error, Equatable { case originalCause, unexpectedDispatch, mainThread }

private func emptyCatalogFixture() throws -> AnimationAuthoringCatalog {
    try AnimationAuthoringCatalog(
        clips: [], surfaceMaterials: [],
        timing: AnimationTimingDefinition(
            minimumSeconds: 0.01, maximumSeconds: 59.99, decimalPlaces: 2, secondsStep: 0.1,
            minimumFrames: 1, maximumFrames: 4999, framesStep: 5))
}

private struct FixtureCatalogCopy: AnimationCatalogCopying {
    let failure: CatalogCopyFixtureError?
    func copy() async throws -> AnimationAuthoringCatalog {
        if let failure { throw failure }
        return try copySynchronously()
    }
    private func copySynchronously() throws -> AnimationAuthoringCatalog {
        guard !Thread.isMainThread else { throw CatalogCopyFixtureError.mainThread }
        return try emptyCatalogFixture()
    }
}

private actor SuspendedCatalogCopy: AnimationCatalogCopying {
    private var started = false
    private var start: CheckedContinuation<Void, Never>?
    private var pending: CheckedContinuation<Void, Never>?
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { start = $0 }
    }
    func release() {
        pending?.resume()
        pending = nil
    }
    func copy() async throws -> AnimationAuthoringCatalog {
        started = true
        start?.resume()
        start = nil
        await withCheckedContinuation { pending = $0 }
        return try emptyCatalogFixture()
    }
}

@MainActor
final class NativeAnimationCatalogLoaderTests: XCTestCase {
    func testInjectedCopyRunsOffMainAndPreservesOriginalFailure() async throws {
        let loader = NativeAnimationCatalogLoader(operation: FixtureCatalogCopy(failure: nil))
        let catalog = try await loader.load()
        XCTAssertTrue(catalog.clips.isEmpty)
        let failed = NativeAnimationCatalogLoader(operation: FixtureCatalogCopy(failure: .originalCause))
        do {
            _ = try await failed.load()
            XCTFail("Original copy cause must propagate")
        } catch { XCTAssertEqual(error as? CatalogCopyFixtureError, .originalCause) }
    }

    func testCancellationBeforeDispatchDoesNotCallTheInjectedOperation() async throws {
        let loader = NativeAnimationCatalogLoader(operation: FixtureCatalogCopy(failure: .unexpectedDispatch))
        let operation = Task { try await loader.load() }
        operation.cancel()
        do {
            _ = try await operation.value
            XCTFail("Cancelled query cannot dispatch copy")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testCancellationAfterSuspendedFakeCopyRejectsItsLateResult() async throws {
        let copy = SuspendedCatalogCopy()
        let loader = NativeAnimationCatalogLoader(operation: copy)
        let operation = Task { try await loader.load() }
        await copy.waitUntilStarted()
        operation.cancel()
        await copy.release()
        do {
            _ = try await operation.value
            XCTFail("Late copied metadata must not publish after cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testCopyBudgetChecksCumulativeSlotsAndOverflowWithoutAllocatingPayloads() throws {
        var budget = try AnimationCatalogCopyBudget(maximumBytes: 32)
        try budget.consumeRecords(count: 2, stride: 8)
        try budget.consume(8)
        XCTAssertEqual(budget.remainingBytes, 8)
        for count in [-1, 9, Int.max] {
            XCTAssertThrowsError(try budget.consume(count)) {
                XCTAssertEqual($0 as? AnimationCatalogError, .limitExceeded)
            }
            XCTAssertEqual(budget.remainingBytes, 8)
        }
        XCTAssertThrowsError(try budget.consumeRecords(count: Int.max, stride: 8))
        XCTAssertThrowsError(try budget.consumeRecords(count: -1, stride: 8))
        XCTAssertThrowsError(try budget.consumeRecords(count: 1, stride: -1))
        XCTAssertEqual(budget.remainingBytes, 8)
        try budget.consume(8)
        try budget.consume(0)
        XCTAssertEqual(budget.remainingBytes, 0)
        for maximum in [0, -1, Int.max] {
            XCTAssertThrowsError(try AnimationCatalogCopyBudget(maximumBytes: maximum))
        }
    }
}
