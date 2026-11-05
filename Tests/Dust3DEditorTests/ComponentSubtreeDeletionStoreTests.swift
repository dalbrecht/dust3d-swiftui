import AppKit
import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import SwiftUI
import XCTest

@testable import Dust3DEditor

private struct DeletionNoNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
    ArchiveImportedMaterialLoading, AnimationCatalogLoading
{
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult { throw CancellationError() }
    func load() async throws -> AnimationAuthoringCatalog { throw CancellationError() }
    func reset(scopeID: UUID) async throws {}
    func load(data: Data, options: MeshBakeOptions, limits: ArchiveTextureLimits) async throws -> MeshWithBakedTextures
    {
        throw CancellationError()
    }
    func load(data: Data, options: SourceMeshBakeOptions, limits: ArchiveSourceTextureLimits) async throws
        -> SourceBakedMesh
    {
        throw CancellationError()
    }
    func loadIfPresent(data: Data, limits: ImportedMaterialRenderLimits) async throws -> ImportedMaterialRenderData? {
        nil
    }
}

@MainActor final class ComponentSubtreeDeletionStoreTests: XCTestCase {
    private func source() throws -> Dust3DDocument {
        let xml = Data(
            """
            <canvas rigType='Biped'><nodes><node id='n' partId='p' x='.3' y='.3' z='.5' radius='.1'/></nodes><edges/><parts><part id='p' locked='true' disabled='true' visible='false'/></parts><components><component id='g' name='Group' linkDataType='future' linkData='opaque'><component id='leaf' linkDataType='partId' linkData='p'/></component><component id='keep' name='Keep'/></components><animations><animation id='motion' type='future' node='n'/></animations></canvas>
            """.utf8)
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(xml.count)'/><asset name='opaque.bin' offset='\(xml.count)' size='4'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + xml + Data([0, 255, 10, 128]))
    }
    private func store() -> EditorStore {
        let stub = DeletionNoNative()
        return EditorStore(
            preview: stub, materialBaker: stub, importedMaterialLoader: stub,
            sourceMaterialBaker: stub, animationCatalog: stub)
    }
    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating && !store.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Deletion Store did not settle")
    }
    func testContextualRowActionDoesNotDeleteEarlierSelectionAndPublishesOneExactUndo() async throws {
        let original = try source()
        let value = store()
        let other = store()
        defer {
            value.stop()
            other.stop()
        }
        await value.load(data: original.encoded())
        await other.load(data: original.encoded())
        try await settle(value)
        try await settle(other)
        value.selectComponents(["keep"])
        try await settle(value)
        let snapshot = try XCTUnwrap(value.snapshot)
        let target = ComponentDeletionTarget(snapshot: snapshot, componentIDs: ["g", "leaf"])
        XCTAssertTrue(value.canDeleteComponentSubtrees(target))
        var published: [Data] = []
        value.onDocumentChanged = { published.append($0) }
        value.componentDeletionAction(target)()
        XCTAssertFalse(value.canDeleteComponentSubtrees(target))
        try await settle(value)
        XCTAssertEqual(value.snapshot?.componentTree.rows.map(\.id), ["keep"])
        XCTAssertEqual(value.snapshot?.selectedComponentIDs, ["keep"])
        XCTAssertTrue(value.snapshot?.nodes.isEmpty == true)
        XCTAssertEqual(published.count, 1)
        XCTAssertEqual(value.snapshot?.document.asset(named: "opaque.bin"), Data([0, 255, 10, 128]))
        XCTAssertEqual(other.snapshot?.document.encoded(), original.encoded())
        value.undo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
        XCTAssertEqual(value.snapshot?.selectedComponentIDs, ["keep"])
        XCTAssertFalse(value.canUndo)
    }
    func testRetainedCallbacksRejectReplacementSelectionConstraintABAInitialBusyAndStop() async throws {
        let original = try source()
        for change in 0..<5 {
            let value = store()
            defer { value.stop() }
            await value.load(data: original.encoded())
            try await settle(value)
            value.selectComponents(["keep"])
            try await settle(value)
            let target = ComponentDeletionTarget(snapshot: try XCTUnwrap(value.snapshot), componentIDs: ["g"])
            if change == 3 { value.selectComponents(["keep"]) }
            let action = value.componentDeletionAction(target)
            switch change {
            case 0:
                await value.load(data: original.encoded())
                try await settle(value)
                value.selectComponents(["keep"])
                try await settle(value)
            case 1:
                value.selectComponents(["g"])
                try await settle(value)
                value.selectComponents(["keep"])
                try await settle(value)
            case 2:
                value.setLock(.x, isLocked: true)
                try await settle(value)
                value.setLock(.x, isLocked: false)
                try await settle(value)
            case 3: try await settle(value)
            default: value.stop()
            }
            action()
            try await settle(value)
            XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
            XCTAssertFalse(value.canUndo)
        }
    }
    func testGraphDeleteDeclinesSidebarTextAndAnimationFocusWithoutNewGlobalComponentShortcut() {
        XCTAssertTrue(
            EditorCommandScope.allowsGraphDelete(
                animationFocus: false, nativeTextFocus: false, componentSidebarFocus: false))
        XCTAssertFalse(
            EditorCommandScope.allowsGraphDelete(
                animationFocus: false, nativeTextFocus: false, componentSidebarFocus: true))
        XCTAssertFalse(
            EditorCommandScope.allowsGraphDelete(
                animationFocus: false, nativeTextFocus: true, componentSidebarFocus: false))
        XCTAssertFalse(
            EditorCommandScope.allowsGraphDelete(
                animationFocus: true, nativeTextFocus: false, componentSidebarFocus: false))
        XCTAssertEqual(ComponentDeletionPresentation.title(rootCount: 1), "Delete Component and Contents")
        XCTAssertEqual(ComponentDeletionPresentation.title(rootCount: 2), "Delete 2 Components and Contents")
    }
    func testHostedSidebarKeepsTheSameFocusedListAcrossAnExplicitContextualActionAndUndo() async throws {
        let original = try source()
        let value = store()
        defer { value.stop() }
        await value.load(data: original.encoded())
        try await settle(value)
        value.selectComponents(["g"])
        try await settle(value)
        let host = NSHostingView(rootView: ComponentSidebar(store: value).frame(width: 320, height: 260))
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 320, height: 260),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer {
            window.contentView = nil
            window.close()
        }
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        func table(in view: NSView) -> NSTableView? {
            if let result = view as? NSTableView { return result }
            return view.subviews.lazy.compactMap { table(in: $0) }.first
        }
        let list = try XCTUnwrap(table(in: host))
        XCTAssertEqual(list.selectedRow, 0)
        XCTAssertTrue(window.makeFirstResponder(list))
        // This offscreen host has no key scene: it proves native focus preservation,
        // not SwiftUI onDeleteCommand delivery. The explicit action uses the same captured target.
        XCTAssertFalse(window.isKeyWindow)
        XCTAssertFalse(NSApp.keyWindow === window)
        let target = ComponentDeletionTarget(snapshot: try XCTUnwrap(value.snapshot), componentIDs: ["g"])
        value.componentDeletionAction(target)()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.componentTree.rows.map(\.id), ["keep"])
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(table(in: host) === list)
        XCTAssertTrue(window.firstResponder === list)
        value.undo()
        try await settle(value)
        XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
        XCTAssertTrue(value.snapshot?.selectedComponentIDs.isEmpty == true)
    }
    func testHostedDestructiveControlRendersBothAppearancesAndRenderingNeverChangesDocument() async throws {
        let original = try source()
        let value = store()
        defer { value.stop() }
        await value.load(data: original.encoded())
        try await settle(value)
        value.selectComponents(["g", "leaf"])
        try await settle(value)
        let target = ComponentDeletionTarget(snapshot: try XCTUnwrap(value.snapshot))
        for scheme in [ColorScheme.light, .dark] {
            let png = try InspectorRenderer.png(
                ComponentDeletionButton(store: value, target: target), width: 320, scheme: scheme)
            XCTAssertGreaterThan(png.count, 1000)
            if let output = ProcessInfo.processInfo.environment["DUST3D_UI_QA_OUTPUT_DIR"] {
                try png.write(
                    to: URL(fileURLWithPath: output).appendingPathComponent(
                        "component-delete-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
        XCTAssertEqual(value.snapshot?.document.encoded(), original.encoded())
        XCTAssertFalse(value.canUndo)
    }
}
