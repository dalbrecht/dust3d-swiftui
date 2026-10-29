import AppKit
import Dust3DDocument
import Dust3DKit
import SwiftUI
import XCTest

@testable import Dust3DEditor

private enum CatalogStateFixtureError: LocalizedError, Equatable {
    case original
    var errorDescription: String? { "Original catalog fixture cause: definitions are unavailable." }
}

private actor ControlledAuthoringCatalog: AnimationCatalogLoading {
    private(set) var calls = 0
    var failure: CatalogStateFixtureError?
    private let suspended: Bool
    private var start: CheckedContinuation<Void, Never>?
    private var pending: CheckedContinuation<Void, Never>?
    init(suspended: Bool = false, failure: CatalogStateFixtureError? = nil) {
        self.suspended = suspended
        self.failure = failure
    }
    func waitUntilStarted() async {
        if calls > 0 { return }
        await withCheckedContinuation { start = $0 }
    }
    func release() {
        pending?.resume()
        pending = nil
    }
    func setFailure(_ failure: CatalogStateFixtureError?) { self.failure = failure }
    func load() async throws -> AnimationAuthoringCatalog {
        calls += 1
        start?.resume()
        start = nil
        if suspended { await withCheckedContinuation { pending = $0 } }
        if let failure { throw failure }
        return try AnimationAuthoringCatalog(
            clips: [], surfaceMaterials: [],
            timing: AnimationTimingDefinition(
                minimumSeconds: 0.01, maximumSeconds: 59.99, decimalPlaces: 2, secondsStep: 0.1,
                minimumFrames: 1, maximumFrames: 4999, framesStep: 5))
    }
}

@MainActor
final class EditorAnimationCatalogStateTests: XCTestCase {
    func testOneOwnedQueryDrainsBeforeAvailabilityAndSuccessfulMetadataIsCached() async throws {
        let service = ControlledAuthoringCatalog(suspended: true)
        let state = EditorAnimationCatalogState(service: service)
        defer { state.stop() }
        let operation = try XCTUnwrap(state.load())
        await service.waitUntilStarted()
        XCTAssertTrue(state.isLoading)
        XCTAssertFalse(state.canLoad)
        let duplicate = try XCTUnwrap(state.load())
        let calls = await service.calls
        XCTAssertEqual(calls, 1)
        await service.release()
        await operation.value
        await duplicate.value
        XCTAssertFalse(state.isLoading)
        XCTAssertNotNil(state.catalog)
        XCTAssertNil(state.issue)
        XCTAssertNil(state.load())
        let cachedCalls = await service.calls
        XCTAssertEqual(cachedCalls, 1)
    }

    func testOriginalFailureRemainsRetryableAndSuccessClearsOnlyCatalogIssue() async throws {
        let service = ControlledAuthoringCatalog(failure: .original)
        let state = EditorAnimationCatalogState(service: service)
        defer { state.stop() }
        await state.load()?.value
        XCTAssertEqual(state.issue as? CatalogStateFixtureError, .original)
        XCTAssertTrue(state.canLoad)
        XCTAssertNil(state.catalog)
        await service.setFailure(nil)
        await state.load()?.value
        XCTAssertNil(state.issue)
        XCTAssertNotNil(state.catalog)
    }

    func testStopBeforeFirstTurnNeverDispatchesAndStoppedStateCannotRestart() async throws {
        let service = ControlledAuthoringCatalog()
        let state = EditorAnimationCatalogState(service: service)
        let operation = try XCTUnwrap(state.load())
        state.stop()
        await operation.value
        let calls = await service.calls
        XCTAssertEqual(calls, 0)
        XCTAssertNil(state.catalog)
        XCTAssertNil(state.issue)
        XCTAssertFalse(state.canLoad)
        XCTAssertNil(state.load())
    }

    func testStopRetainsDrainOwnershipAndRejectsLateFakeMetadataWithoutHumanInput() async throws {
        let service = ControlledAuthoringCatalog(suspended: true)
        let state = EditorAnimationCatalogState(service: service)
        let operation = try XCTUnwrap(state.load())
        await service.waitUntilStarted()
        state.stop()
        XCTAssertTrue(state.isLoading)
        XCTAssertNotNil(state.task)
        XCTAssertNil(state.load())
        await service.release()
        await operation.value
        XCTAssertFalse(state.isLoading)
        XCTAssertNil(state.task)
        XCTAssertNil(state.catalog)
        XCTAssertNil(state.issue)
    }

    func testUnboundSessionReportsAvailabilityWithoutDispatchingNativeCode() async throws {
        let state = EditorAnimationCatalogState(service: nil)
        defer { state.stop() }
        XCTAssertNil(state.load())
        XCTAssertFalse(state.canLoad)
        XCTAssertEqual(state.issue as? EditorAnimationCatalogError, .unavailable)
    }
    func testLoadingAndErrorControlsRenderOffscreenWithOnlyInjectedCatalogs() async throws {
        for state in ["loading", "error"] {
            let service = ControlledAuthoringCatalog(suspended: state == "loading", failure: .original)
            let store = EditorStore(animationCatalog: service)
            defer { store.stop() }
            let operation = try XCTUnwrap(store.authoringCatalog.load())
            if state == "loading" { await service.waitUntilStarted() } else { await operation.value }
            let workflow = EditorAnimationAuthoringWorkflow(store: store)
            for scheme in [ColorScheme.light, .dark] {
                let png = try InspectorRenderer.png(
                    AnimationAuthoringControls(store: store, workflow: workflow), width: 250, scheme: scheme)
                XCTAssertNotNil(NSBitmapImageRep(data: png))
                if let path = ProcessInfo.processInfo.environment["DUST3D_UI_QA_OUTPUT_DIR"] {
                    let root = URL(fileURLWithPath: path, isDirectory: true)
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                    try png.write(
                        to: root.appendingPathComponent(
                            "animation-authoring-\(state)-\(scheme == .dark ? "dark" : "light").png"), options: .atomic)
                }
            }
            workflow.stop()
            store.stop()
            if state == "loading" {
                await service.release()
                await operation.value
            }
        }
    }

}
