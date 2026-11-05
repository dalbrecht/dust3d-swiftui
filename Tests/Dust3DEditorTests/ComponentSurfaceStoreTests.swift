import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

@MainActor final class ComponentSurfaceStoreTests: XCTestCase {
    private enum Failure: Error { case timeout }
    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<800 {
            if !store.isWorking && !store.isGenerating && !store.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Finish command and material bake did not settle")
        throw Failure.timeout
    }
    private func prepare(_ bytes: Data, baker: ReviewedSurfaceBake) async throws -> EditorStore {
        let store = EditorStore(materialBaker: baker)
        await store.load(data: bytes)
        try await settle(store)
        store.selectComponent(SurfaceDetailFixtureVariants.groupID)
        try await settle(store)
        XCTAssertNil(store.errorMessage)
        XCTAssertNil(store.materialIssue)
        return store
    }
    private func change(_ store: EditorStore, edit: ComponentSurfaceEdit, expected: Data) async throws
        -> MeshWithBakedTextures
    {
        let before = try XCTUnwrap(store.snapshot)
        let revision = store.previewRevision
        store.componentSurfaceAction(edit, target: .init(snapshot: before))()
        try await settle(store)
        XCTAssertNil(store.errorMessage)
        XCTAssertNil(store.materialIssue)
        let result = try XCTUnwrap(store.snapshot)
        XCTAssertEqual(result.document.encoded(), expected)
        XCTAssertEqual(result.previewIdentity.geometry, before.previewIdentity.geometry)
        XCTAssertNotEqual(result.previewIdentity.materials, before.previewIdentity.materials)
        XCTAssertEqual(
            store.previewRevision, revision,
            "A finish changes baked pixels without regenerating the visible geometry pass")
        return try XCTUnwrap(store.bakedMesh)
    }

    func testAllCoatPatternsAndInkSizeBellyActionsChangeRealBakedColorWithOneStepHistoryAndReopen() async throws {
        let inputs = try ReviewedSurfaceBake.inputs()
        let base = try XCTUnwrap(inputs["skin-none"])
        for pattern in ComponentSurfacePattern.allCases where pattern != .none {
            let baker = ReviewedSurfaceBake()
            let store = try await prepare(base, baker: baker)
            defer { store.stop() }
            let prior = try XCTUnwrap(store.bakedMesh)
            let expected = try XCTUnwrap(inputs["skin-" + pattern.rawValue])
            let changed = try await change(store, edit: .pattern(pattern), expected: expected)
            XCTAssertNotEqual(changed.textures.color.pixels, prior.textures.color.pixels)
            XCTAssertNil(changed.textures.normal)
            XCTAssertEqual(changed.geometry.triangleCount, prior.geometry.triangleCount)
            XCTAssertEqual(store.snapshot?.document.asset(named: "opaque.bin"), Data([0, 255, 10, 128]))
            store.undo()
            try await settle(store)
            XCTAssertEqual(store.snapshot?.document.encoded(), base)
            XCTAssertFalse(store.snapshot?.canUndo == true)
            store.redo()
            try await settle(store)
            XCTAssertEqual(store.snapshot?.document.encoded(), expected)
            let reopened = try await prepare(expected, baker: baker)
            defer { reopened.stop() }
            XCTAssertEqual(reopened.bakedMesh?.textures.color.pixels, changed.textures.color.pixels)
        }
        let spots = try XCTUnwrap(inputs["skin-Spots"])
        let edits: [(String, ComponentSurfaceEdit)] = [
            ("skin-ink-red", .ink(.init(red: 200, green: 20, blue: 30))),
            ("skin-size-small", .scalar(.patternScale, 0.03)), ("skin-size-large", .scalar(.patternScale, 0.12)),
            ("skin-belly", .scalar(.belly, 1)),
        ]
        for (name, edit) in edits {
            let baker = ReviewedSurfaceBake()
            let store = try await prepare(spots, baker: baker)
            defer { store.stop() }
            let originalPixels = try XCTUnwrap(store.bakedMesh?.textures.color.pixels)
            let changed = try await change(store, edit: edit, expected: XCTUnwrap(inputs[name]))
            XCTAssertNotEqual(changed.textures.color.pixels, originalPixels, name)
            XCTAssertNil(changed.textures.normal)
            let received = await baker.received
            XCTAssertEqual(received.last, ReviewedSurfaceBake.hash(try XCTUnwrap(inputs[name])))
        }
    }

    func testActualClothActionsRefreshGeneratedNormalStrengthAndSizeWithoutStaleGeometryOrFoldCache() async throws {
        let inputs = try ReviewedSurfaceBake.inputs()
        let start = try XCTUnwrap(inputs["cloth-start"])
        let full = try XCTUnwrap(inputs["cloth-action-full"])
        let baker = ReviewedSurfaceBake()
        let store = try await prepare(start, baker: baker)
        defer { store.stop() }
        XCTAssertNil(store.bakedMesh?.textures.normal)
        let changed = try await change(store, edit: .scalar(.wrinkles, 1), expected: full)
        let normal = try XCTUnwrap(changed.textures.normal)
        let nonflat = stride(from: 0, to: normal.pixels.count, by: 4).filter { (index: Int) -> Bool in
            let redDeviation = abs(Int(normal.pixels[index]) - 128)
            let greenDeviation = abs(Int(normal.pixels[index + 1]) - 128)
            return normal.pixels[index + 3] == 255 && (redDeviation > 2 || greenDeviation > 2)
        }.count
        XCTAssertGreaterThan(nonflat, 0)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), start)
        XCTAssertNil(store.bakedMesh?.textures.normal)
        store.redo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), full)
        XCTAssertEqual(store.bakedMesh?.textures.normal, normal)
        for (name, edit) in [
            ("cloth-action-half", ComponentSurfaceEdit.scalar(.wrinkles, 0.5)),
            ("cloth-action-size", .scalar(.wrinkleSize, 2)),
        ] {
            let next = try await prepare(full, baker: baker)
            defer { next.stop() }
            let baked = try await change(next, edit: edit, expected: XCTUnwrap(inputs[name]))
            let updatedNormal = try XCTUnwrap(baked.textures.normal)
            XCTAssertNotEqual(updatedNormal.pixels, normal.pixels, name)
            let reopened = try await prepare(try XCTUnwrap(inputs[name]), baker: baker)
            defer { reopened.stop() }
            XCTAssertEqual(reopened.bakedMesh?.textures.normal, baked.textures.normal)
        }
    }
}
