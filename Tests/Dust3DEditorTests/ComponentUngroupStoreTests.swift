import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import SwiftUI
import XCTest

@testable import Dust3DEditor

private struct UngroupNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
    ArchiveImportedMaterialLoading, AnimationCatalogLoading
{
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult { throw CancellationError() }
    func reset(scopeID: UUID) async throws {}
    func load() async throws -> AnimationAuthoringCatalog { throw CancellationError() }
    func load(data: Data, options: MeshBakeOptions, limits: ArchiveTextureLimits) async throws -> MeshWithBakedTextures
    { throw CancellationError() }
    func load(data: Data, options: SourceMeshBakeOptions, limits: ArchiveSourceTextureLimits) async throws
        -> SourceBakedMesh
    { throw CancellationError() }
    func loadIfPresent(data: Data, limits: ImportedMaterialRenderLimits) async throws -> ImportedMaterialRenderData? {
        nil
    }
}
@MainActor final class ComponentUngroupStoreTests: XCTestCase {
    private func source() throws -> Dust3DDocument {
        let xml = Data(
            "<canvas><nodes><node id='n' partId='p' x='.5' y='.5' z='.5' radius='.1'/></nodes><edges/><parts><part id='p' locked='true' disabled='true' visible='false'/></parts><components><component id='a' linkDataType='future' linkData='opaque'><component id='keep'><component id='b' linkDataType='partId' linkData='p'><component id='child'/></component></component></component><component id='leaf' linkDataType='partId' linkData='p'/></components></canvas>"
                .utf8)
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(xml.count)'/><asset name='opaque.bin' offset='\(xml.count)' size='4'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + xml + Data([0, 255, 10, 128]))
    }
    private func store() -> EditorStore {
        let stub = UngroupNoNative()
        return EditorStore(
            preview: stub, materialBaker: stub, importedMaterialLoader: stub, sourceMaterialBaker: stub,
            animationCatalog: stub)
    }
    private func settle(_ value: EditorStore) async throws {
        for _ in 0..<300 {
            if !value.isWorking && !value.isGenerating && !value.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Ungroup Store did not settle")
    }
    func testOneAndMultipleLoadedWrappersUseUnifiedActionWithoutDummySiblingAndOnePublication() async throws {
        for ids: Set<String> in [["a"], ["a", "b", "leaf"]] {
            let value = store()
            let other = store()
            let original = try source()
            defer {
                value.stop()
                other.stop()
            }
            await value.load(data: original.encoded())
            await other.load(data: original.encoded())
            try await settle(value)
            try await settle(other)
            value.selectComponents(ids)
            try await settle(value)
            XCTAssertTrue(value.canUngroupComponent)
            var publications = 0
            value.onDocumentChanged = { _ in publications += 1 }
            value.ungroupSelectedComponent()
            try await settle(value)
            XCTAssertEqual(publications, 1)
            XCTAssertFalse(value.snapshot?.componentTree.rows.contains { $0.id == "a" } == true)
            if ids.contains("b") {
                XCTAssertFalse(value.snapshot?.componentTree.rows.contains { $0.id == "b" } == true)
            }
            XCTAssertEqual(other.snapshot?.document.encoded(), original.encoded())
            XCTAssertEqual(value.snapshot?.document.asset(named: "opaque.bin"), Data([0, 255, 10, 128]))
            value.undo()
            try await settle(value)
            XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
            XCTAssertFalse(value.canUndo)
        }
    }
    func testContextMenuRowDoesNotRetargetEarlierGlobalSelectionAndCountUsesEveryExplicitWrapper() async throws {
        let value = store()
        let original = try source()
        defer { value.stop() }
        await value.load(data: original.encoded())
        try await settle(value)
        value.selectComponents(["leaf"])
        try await settle(value)
        let snapshot = try XCTUnwrap(value.snapshot)
        let target = ComponentUngroupTarget(snapshot: snapshot, componentIDs: ["a"])
        XCTAssertEqual(target.wrapperCount, 1)
        XCTAssertTrue(value.canUngroupComponents(target))
        XCTAssertFalse(value.canUngroupComponent)
        value.componentUngroupAction(target)()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.selectedComponentIDs, ["leaf"])
        XCTAssertEqual(value.snapshot?.componentTree.rows.map(\.id), ["keep", "b", "child", "leaf"])
        XCTAssertEqual(ComponentUngroupPresentation.title(wrapperCount: 2), "Ungroup 2 Components")
        XCTAssertEqual(ComponentUngroupPresentation.title(wrapperCount: 1), "Ungroup Component")
    }
    func testRetainedSelectionConstraintDocumentLoadABAInitialBusyAndStopNeverRetarget() async throws {
        for change in 0..<6 {
            let value = store()
            let original = try source()
            defer { value.stop() }
            await value.load(data: original.encoded())
            try await settle(value)
            value.selectComponents(["a"])
            try await settle(value)
            let target = ComponentUngroupTarget(snapshot: try XCTUnwrap(value.snapshot))
            if change == 4 { value.selectComponents(["a"]) }
            let action = value.componentUngroupAction(target)
            switch change {
            case 0:
                value.selectComponents(["leaf"])
                try await settle(value)
                value.selectComponents(["a"])
            case 1:
                value.setLock(.x, isLocked: true)
                try await settle(value)
                value.setLock(.x, isLocked: false)
            case 2: await value.load(data: original.encoded())
            case 3:
                value.renameComponent("leaf", name: "Changed")
                try await settle(value)
                value.undo()
            case 4: break
            default: value.stop()
            }
            try await settle(value)
            action()
            try await settle(value)
            XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
            XCTAssertFalse(value.canUndo)
        }
    }
    func testTypedInheritedContextFailuresSurfaceTheirActualCauseWithoutHistoryOrDataLoss() async throws {
        for (body, expected) in [
            (
                "<component id='g' xml:lang='fr'><component id='c'/></component>",
                "Cannot ungroup g without changing inherited xml:lang. The source is unchanged."
            ),
            (
                "<component id='g' xmlns:q='urn:removed'>q:Value</component>",
                "Cannot ungroup g without changing the namespace context of its text. The source is unchanged."
            ),
        ] {
            let value = store()
            defer { value.stop() }
            let original = try Dust3DDocument(
                snapshotXML: Data("<canvas><nodes/><edges/><parts/><components>\(body)</components></canvas>".utf8))
            await value.load(data: original.encoded())
            try await settle(value)
            let target = ComponentUngroupTarget(snapshot: try XCTUnwrap(value.snapshot), componentIDs: ["g"])
            value.componentUngroupAction(target)()
            try await settle(value)
            XCTAssertEqual(value.errorMessage, expected)
            XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
            XCTAssertFalse(value.canUndo)
        }
    }
    func testSingleAndMultipleControlsRenderBothAppearancesWithoutParsingOrMutatingXML() async throws {
        let value = store()
        let original = try source()
        defer { value.stop() }
        await value.load(data: original.encoded())
        try await settle(value)
        for ids: Set<String> in [["a"], ["a", "b"]] {
            value.selectComponents(ids)
            try await settle(value)
            let target = ComponentUngroupTarget(snapshot: try XCTUnwrap(value.snapshot))
            for scheme in [ColorScheme.light, .dark] {
                let png = try InspectorRenderer.png(
                    ComponentUngroupButton(store: value, target: target), width: 320, scheme: scheme)
                XCTAssertGreaterThan(png.count, 1000)
                if let directory = ProcessInfo.processInfo.environment["DUST3D_UI_QA_OUTPUT_DIR"] {
                    try png.write(
                        to: URL(fileURLWithPath: directory).appendingPathComponent(
                            "ungroup-\(target.wrapperCount)-\(scheme == .dark ? "dark" : "light").png"))
                }
            }
        }
        XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
        XCTAssertFalse(value.canUndo)
    }
}
