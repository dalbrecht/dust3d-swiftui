import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

/// CPU-only production SDK proof; unresolved generated-node hints remain explicitly unresolved.
@MainActor final class WrappingBodyBindingNativeTests: XCTestCase {
    private enum Failure: Error { case timeout, invalidNormal }
    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<1200 {
            if !store.isWorking && !store.isGenerating && !store.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw Failure.timeout
    }
    private func store() -> EditorStore {
        let boundary = ReviewedBodyBindingNative()
        return EditorStore(
            preview: boundary, materialBaker: boundary,
            importedMaterialLoader: boundary, sourceMaterialBaker: boundary)
    }
    private func assertResolvedDonors(_ store: EditorStore, partID: String, expectsUnknown: Bool) throws {
        let hints = try XCTUnwrap(store.previewSourceHints)
        var resolved = 0
        var unknown = 0
        for corner in hints.corners where corner.kind == .weightedHint {
            for influence in hints.influences[corner.influenceRange] {
                XCTAssertTrue(influence.weight.isFinite && influence.weight >= 0)
                if let identity = influence.identityIndex {
                    XCTAssertEqual(hints.identities[identity].partID, partID)
                    resolved += 1
                } else {
                    unknown += 1
                }
            }
        }
        XCTAssertGreaterThan(resolved, 0)
        if expectsUnknown {
            XCTAssertGreaterThan(unknown, 0, "Generated donor nodes are not original source catalog identities")
        }
    }
    func testRealStoreBindingChangesResolvedDonorsAndFreshNormalMapWithOneUndoAndReopen() async throws {
        let inputs = try BodyBindingFixtureFamily.inputs()
        for bytes in inputs.values { try ReviewedBodyBindingNative.admit(bytes) }
        let value = store()
        let reopened = store()
        defer {
            value.stop()
            reopened.stop()
        }
        await value.load(data: try XCTUnwrap(inputs["own"]))
        try await settle(value)
        XCTAssertNil(value.errorMessage)
        try assertResolvedDonors(value, partID: BodyBindingFixtureFamily.guidePartID, expectsUnknown: false)
        XCTAssertNil(value.materialIssue)
        let originalBaked = try XCTUnwrap(value.bakedMesh)
        let originalNormal = originalBaked.textures.normal?.pixels
        value.selectComponent(BodyBindingFixtureFamily.garmentID)
        try await settle(value)
        let before = try XCTUnwrap(value.snapshot)
        value.componentWrapBindingAction(.group(BodyBindingFixtureFamily.bodyID), target: .init(snapshot: before))()
        try await settle(value)
        XCTAssertNil(value.errorMessage)
        XCTAssertEqual(value.snapshot?.document.encoded(), inputs["body"])
        XCTAssertNotEqual(value.snapshot?.previewIdentity.geometry, before.previewIdentity.geometry)
        XCTAssertNotEqual(value.snapshot?.previewIdentity.materials, before.previewIdentity.materials)
        try assertResolvedDonors(value, partID: BodyBindingFixtureFamily.bodyPartID, expectsUnknown: true)
        XCTAssertNil(value.materialIssue)
        let boundBaked = try XCTUnwrap(value.bakedMesh)
        let normal = try XCTUnwrap(boundBaked.textures.normal)
        guard normal.width > 0, normal.height > 0, normal.rowStride == normal.width * 4,
            normal.pixels.count == normal.rowStride * normal.height
        else { throw Failure.invalidNormal }
        var normalDirections = Set<UInt32>()
        var opaque = 0
        var nonflat = 0
        for index in stride(from: 0, to: normal.pixels.count, by: 4) {
            let r = normal.pixels[index]
            let g = normal.pixels[index + 1]
            let b = normal.pixels[index + 2]
            guard normal.pixels[index + 3] == 255, b > 0 else { continue }
            opaque += 1
            normalDirections.insert(UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b))
            if !(127...128).contains(r) || !(127...128).contains(g) || b < 254 { nonflat += 1 }
        }
        print("Body binding normal: opaque=\(opaque), nonflat=\(nonflat), distinct=\(normalDirections.count)")
        XCTAssertGreaterThan(opaque, 0)
        XCTAssertGreaterThan(nonflat, 0, "Bound folds must perturb valid opaque normal texels")
        XCTAssertGreaterThan(normalDirections.count, 1, "Bound folds must vary across valid opaque normal texels")
        XCTAssertNotEqual(normal.pixels, originalNormal)
        await reopened.load(data: try XCTUnwrap(inputs["body"]))
        try await settle(reopened)
        XCTAssertNil(reopened.materialIssue)
        let reopenedBaked = try XCTUnwrap(reopened.bakedMesh)
        XCTAssertEqual(
            reopenedBaked.textures.normal?.pixels, normal.pixels,
            "A material action must match an independent fresh bake of the same exact source")
        try assertResolvedDonors(reopened, partID: BodyBindingFixtureFamily.bodyPartID, expectsUnknown: true)
        value.undo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), inputs["own"])
        XCTAssertFalse(value.canUndo)
        XCTAssertNil(value.materialIssue)
        let undoneBaked = try XCTUnwrap(value.bakedMesh)
        XCTAssertEqual(undoneBaked.textures.normal?.pixels, originalNormal)
        try assertResolvedDonors(value, partID: BodyBindingFixtureFamily.guidePartID, expectsUnknown: false)
        XCTAssertEqual(value.snapshot?.document.asset(named: "opaque.bin"), Data([0, 255, 10, 128]))
    }
}
