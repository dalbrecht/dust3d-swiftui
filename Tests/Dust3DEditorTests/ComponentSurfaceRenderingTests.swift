import AppKit
import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Dust3DRendering
import Foundation
import Metal
import SwiftUI
import XCTest

@testable import Dust3DEditor

/// Application preparation failure only; the native delegate is never invoked for a rejected continuation.
private actor SurfaceWarningPreparationGate: ArchiveTextureBaking {
    private enum Failure: LocalizedError {
        case original
        var errorDescription: String? { "Original material preparation cause" }
    }
    private let delegate = ReviewedSurfaceBake()
    private var holdNext = false
    private var pending: CheckedContinuation<Void, any Error>?
    var isPending: Bool { pending != nil }
    func suspendNext() { holdNext = true }
    func rejectPending() {
        let continuation = pending
        pending = nil
        continuation?.resume(throwing: Failure.original)
    }
    func load(data: Data, options: MeshBakeOptions, limits: ArchiveTextureLimits) async throws -> MeshWithBakedTextures
    {
        if holdNext {
            holdNext = false
            try await withCheckedThrowingContinuation { pending = $0 }
        }
        return try await delegate.load(data: data, options: options, limits: limits)
    }
}

@MainActor final class ComponentSurfaceRenderingTests: XCTestCase {
    private enum Failure: Error { case timeout, unexpectedNormal }
    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<800 {
            if !store.isWorking && !store.isGenerating && !store.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw Failure.timeout
    }
    private func save(_ data: Data, name: String) throws {
        guard let output = ProcessInfo.processInfo.environment["DUST3D_UI_QA_OUTPUT_DIR"] else { return }
        try data.write(to: URL(fileURLWithPath: output).appendingPathComponent(name + ".png"))
    }
    private func save(_ image: FilePreviewImage, name: String) throws {
        let png = try XCTUnwrap(
            NSBitmapImageRep(cgImage: image.makeCGImage()).representation(using: .png, properties: [:]))
        try save(png, name: name)
    }

    func testActualAuthoredPatternRendersThroughProductionEncoderAndOnlyCurrentReceiptClearsSurfaceNotice() async throws
    {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("No Metal device") }
        let inputs = try ReviewedSurfaceBake.inputs()
        let preparation = SurfaceWarningPreparationGate()
        let store = EditorStore(materialBaker: preparation)
        defer { store.stop() }
        await store.load(data: try XCTUnwrap(inputs["skin-none"]))
        try await settle(store)
        let before = try XCTUnwrap(store.bakedMesh)
        guard before.textures.normal == nil else { throw Failure.unexpectedNormal }
        let plain = try await FilePreviewRenderer.render(
            bakedMesh: before, maximumSize: .init(width: 320, height: 320), scale: 1)
        store.selectComponent(SurfaceDetailFixtureVariants.groupID)
        try await settle(store)
        let target = try ComponentSurfaceTarget(snapshot: XCTUnwrap(store.snapshot))
        store.componentSurfaceAction(.pattern(.spots), target: target)()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), inputs["skin-Spots"])
        let baked = try XCTUnwrap(store.bakedMesh)
        // Only root-reviewed color-only inputs may reach this GPU proof. Generated normal maps stay CPU-only.
        guard baked.textures.normal == nil else { throw Failure.unexpectedNormal }
        let revision = store.materialViewportRevision
        let patterned = try await FilePreviewRenderer.render(
            bakedMesh: baked, maximumSize: .init(width: 320, height: 320), scale: 1)
        XCTAssertNotEqual(patterned.pixels, plain.pixels)
        XCTAssertNotNil(store.previewCompatibilityWarning)
        store.materialsRendered(revision: revision - 1)
        XCTAssertNotNil(store.previewCompatibilityWarning)
        store.materialsRendered(revision: revision)
        XCTAssertNil(
            store.previewCompatibilityWarning,
            "Confirmed legacy baked patterns must not retain a false not-displayed notice")
        try save(plain, name: "surface-pattern-before")
        try save(patterned, name: "surface-pattern-after")
        let component = try XCTUnwrap(store.snapshot?.selectedComponent)
        for scheme in [ColorScheme.light, .dark] {
            try save(
                InspectorRenderer.png(
                    ComponentWrappingControls(store: store, component: component), width: 290, scheme: scheme),
                name: "wrapping-finish-\(scheme == .dark ? "dark" : "light")")
        }
        store.materialsFailed("original surface GPU failure", revision: revision)
        XCTAssertNotNil(store.previewCompatibilityWarning)
        XCTAssertEqual(store.materialIssue, "original surface GPU failure")
        await preparation.suspendNext()
        store.retryMaterials()
        XCTAssertTrue(store.materialState.isStale)
        XCTAssertNil(store.previewCompatibilityWarning, "A retained stale CPU value cannot introduce its warning")
        for _ in 0..<300 {
            if await preparation.isPending { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let pending = await preparation.isPending
        guard pending else {
            XCTFail("Preparation did not reach the controlled boundary")
            throw Failure.timeout
        }
        await preparation.rejectPending()
        await store.materialGeneration?.value
        XCTAssertNotNil(store.materialState.value)
        XCTAssertTrue(store.materialState.isStale)
        XCTAssertNil(
            store.previewCompatibilityWarning, "A failed preparation's old output cannot reintroduce stale diagnostics")
        XCTAssertEqual(store.materialIssue, "Original material preparation cause")
    }
}
