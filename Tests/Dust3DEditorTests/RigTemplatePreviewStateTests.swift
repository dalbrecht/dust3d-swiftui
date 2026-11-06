#if MOTE3D_EXPERIMENTAL_RIG_TEMPLATE
    import Foundation
    import XCTest
    @testable import Dust3DEditor
    @testable import Dust3DKit

    // Synchronous sampling verifies this worker's execution without treating thread
    // identity as an async isolation mechanism in production.
    private func templateWorkerThreadMarker() -> String { Thread.isMainThread ? "main" : "background" }

    private actor TemplatePreviewGate {
        var next = 0
        var pending: [String: CheckedContinuation<RigTemplateMesh?, Error>] = [:]
        func load(_ key: String) async throws -> RigTemplateMesh? {
            try await withCheckedThrowingContinuation { pending[key] = $0 }
        }
        func numberedLoad() async throws -> RigTemplateMesh? {
            next += 1
            return try await load(String(next))
        }
        func contains(_ key: String) -> Bool { pending[key] != nil }
        func finish(_ key: String, marker: String) {
            pending.removeValue(forKey: key)?.resume(returning: RigTemplateMesh(vertices: [], boneNames: [marker]))
        }
        func fail(_ key: String) {
            pending.removeValue(forKey: key)?.resume(
                throwing: RigTemplateHierarchyError.invalidMetadata("original cause"))
        }
    }

    @MainActor
    final class RigTemplatePreviewStateTests: XCTestCase {
        private func waitFor(_ key: String, gate: TemplatePreviewGate) async throws {
            for _ in 0..<10000 {
                if await gate.contains(key) { return }
                await Task.yield()
            }
            throw RigTemplateHierarchyError.invalidMetadata("test loader did not start")
        }

        func testExactRequestIdentityPreservesCanonicalUnicodeDistinction() {
            let a = RigTemplatePreviewRequest(sourceType: "Test", selectedBoneName: "é")
            let b = RigTemplatePreviewRequest(sourceType: "Test", selectedBoneName: "é")
            XCTAssertNotEqual(a, b)
            XCTAssertEqual(Set([a, b]).count, 2)
            XCTAssertNotEqual(RigTemplatePreviewRequest(sourceType: nil), RigTemplatePreviewRequest(sourceType: ""))
        }

        func testReplacementRejectsLateSuccessAndLateRenderFailure() async throws {
            let gate = TemplatePreviewGate()
            let state = RigTemplatePreviewState { request in try await gate.load(request.selectedBoneName) }
            let first = Task { await state.load(.init(sourceType: "Test", selectedBoneName: "first")) }
            try await waitFor("first", gate: gate)
            let firstRevision = try XCTUnwrap(state.revision)
            let second = Task { await state.load(.init(sourceType: "Test", selectedBoneName: "second")) }
            try await waitFor("second", gate: gate)
            XCTAssertNil(state.mesh)
            XCTAssertTrue(state.isLoading)
            await gate.finish("second", marker: "current")
            await second.value
            await gate.finish("first", marker: "obsolete")
            await first.value
            XCTAssertEqual(state.mesh?.boneNames, ["current"])
            state.recordRenderFailure("obsolete GPU error", revision: firstRevision)
            XCTAssertNil(state.error)
            let revision = try XCTUnwrap(state.revision)
            state.recordRenderFailure("current GPU cause", revision: revision)
            XCTAssertEqual(state.error, "current GPU cause")
            XCTAssertFalse(state.isLoading)
        }

        func testStopAndCallerCancellationRejectPublicationWithoutAffectingOtherWindow() async throws {
            let gate = TemplatePreviewGate()
            let first = RigTemplatePreviewState { _ in try await gate.load("first") }
            let second = RigTemplatePreviewState { _ in try await gate.load("second") }
            let taskA = Task { await first.load(.init(sourceType: "Snake")) }
            let taskB = Task { await second.load(.init(sourceType: "Bird")) }
            try await waitFor("first", gate: gate)
            try await waitFor("second", gate: gate)
            first.stop()
            await gate.finish("first", marker: "obsolete")
            await taskA.value
            XCTAssertNil(first.mesh)
            XCTAssertNil(first.revision)
            XCTAssertFalse(first.isLoading)
            await gate.finish("second", marker: "other window")
            await taskB.value
            XCTAssertEqual(second.mesh?.boneNames, ["other window"])
            let cancelled = Task { await first.load(.init(sourceType: "Snake")) }
            try await waitFor("first", gate: gate)
            cancelled.cancel()
            await gate.finish("first", marker: "cancelled")
            await cancelled.value
            XCTAssertNil(first.mesh)
            XCTAssertNil(first.error)
            XCTAssertFalse(first.isLoading)
        }

        func testOriginalFailureAndSuccessfulEmptyResultHaveDifferentStates() async throws {
            let gate = TemplatePreviewGate()
            let state = RigTemplatePreviewState { _ in try await gate.load("fail") }
            let failing = Task { await state.load(.init(sourceType: "Test")) }
            try await waitFor("fail", gate: gate)
            await gate.fail("fail")
            await failing.value
            XCTAssertTrue(state.error?.contains("original cause") == true)
            XCTAssertNil(state.mesh)
            let empty = RigTemplatePreviewState { _ in nil }
            await empty.load(.init(sourceType: nil))
            XCTAssertNil(empty.mesh)
            XCTAssertNil(empty.error)
            XCTAssertFalse(empty.isLoading)
        }

        func testABAReturnCannotPublishAnOlderEqualRequest() async throws {
            let gate = TemplatePreviewGate()
            let state = RigTemplatePreviewState { _ in try await gate.numberedLoad() }
            let a = RigTemplatePreviewRequest(sourceType: "Test", selectedBoneName: "é")
            let b = RigTemplatePreviewRequest(sourceType: "Test", selectedBoneName: "é")
            let first = Task { await state.load(a) }
            try await waitFor("1", gate: gate)
            let oldRevision = try XCTUnwrap(state.revision)
            let second = Task { await state.load(b) }
            try await waitFor("2", gate: gate)
            let third = Task { await state.load(a) }
            try await waitFor("3", gate: gate)
            await gate.finish("3", marker: "new A")
            await third.value
            await gate.fail("2")
            await second.value
            await gate.finish("1", marker: "old A")
            await first.value
            XCTAssertEqual(state.request, a)
            XCTAssertEqual(state.mesh?.boneNames, ["new A"])
            state.recordRenderFailure("old A render", revision: oldRevision)
            XCTAssertNil(state.error)
        }

        func testLoaderRunsOffMainThreadAndInvalidPalettePreservesCause() async {
            let state = RigTemplatePreviewState { _ in
                RigTemplateMesh(vertices: [], boneNames: [templateWorkerThreadMarker()])
            }
            await state.load(.init(sourceType: "Test"))
            XCTAssertEqual(state.mesh?.boneNames, ["background"])
            await state.load(
                .init(sourceType: "Test"),
                appearance: .init(
                    boneColor: SIMD4<Float>(.nan, 0, 0, 1), selectedBoneColor: .one, ringColor: .one))
            XCTAssertNil(state.mesh)
            XCTAssertNil(state.displayMesh)
            XCTAssertTrue(state.error?.contains("non-finite template display color") == true)
        }

        func testDefaultTemplateServicePublishesPreparedGeometryAndClearsOnStop() async {
            let state = RigTemplatePreviewState()
            await state.load(
                .init(sourceType: "Snake", selectedBoneName: "Root"),
                appearance: .init(
                    boneColor: SIMD4<Float>(0, 1, 0, 1), selectedBoneColor: SIMD4<Float>(1, 0, 0, 1), ringColor: .one))
            XCTAssertNil(state.error)
            XCTAssertEqual(state.mesh?.boneNames.count, 14)
            XCTAssertEqual(state.displayMesh?.vertices.count, 14 * 1764)
            state.stop()
            XCTAssertNil(state.mesh)
            XCTAssertNil(state.displayMesh)
            XCTAssertNil(state.revision)
            await state.load(.init(sourceType: nil))
            XCTAssertNil(state.error)
            XCTAssertNil(state.mesh)
            await state.load(.init(sourceType: "unsupported"))
            XCTAssertTrue(state.error?.contains("unsupported") == true)
        }
    }
#endif
