import AppKit
import Dust3DDocument
import Dust3DKit
import Foundation
import SwiftUI
import XCTest

@testable import Dust3DEditor

final class RigSettingsStoreTests: XCTestCase {
    private let nodeID = "{11111111-1111-4111-8111-111111111111}"

    private func document() throws -> Dust3DDocument {
        let model = Data(
            "<canvas rigType='future' headHasEyelids='False' future='keep' originX='.5' originY='.5' originZ='.5'><nodes><node id='\(nodeID)' partId='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}' x='.5' y='.5' z='.5' radius='.1'/></nodes><edges/><parts><part id='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}'/></parts><components><component id='{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}' linkDataType='partId' linkData='{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}'/></components><rig future='retain'/><animations future='retain'/></canvas>"
                .utf8)
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(model.count)'/><asset name='opaque.bin' offset='\(model.count)' size='4'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + Data([0, 255, 10, 128]))
    }

    @MainActor private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating && !store.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Stored rig edit or ordinary preview did not settle")
    }

    @MainActor func testStoredRigEditsRetainExactHistorySelectionAssetsAndPreviewWithoutEvaluatingRig() async throws {
        let source = try document()
        let preview = CountingRigPreview()
        let store = EditorStore(preview: preview)
        defer { store.stop() }
        XCTAssertFalse(store.canEditRigSettings)
        store.setRigType(.bird)
        XCTAssertNil(store.errorMessage)
        await store.load(data: source.encoded())
        try await settle(store)
        XCTAssertTrue(store.canEditRigSettings)
        store.select(nodeID)
        try await settle(store)
        store.setLock(.radius, isLocked: true)
        try await settle(store)
        let camera = store.cameraReset
        let previewRevision = store.previewRevision
        let materialRevision = store.materialViewportRevision
        let positions = try XCTUnwrap(store.mesh).vertices.map(\.position)
        var publications: [Data] = []
        store.onDocumentChanged = { publications.append($0) }
        store.setRigType(.bird)
        XCTAssertFalse(store.canEditRigSettings)
        store.setHeadHasEyelids(true)
        try await settle(store)
        XCTAssertEqual(store.snapshot?.rigSettings.rigType, .bird)
        XCTAssertFalse(try XCTUnwrap(store.snapshot).rigSettings.headHasEyelids)
        store.setRigType(.bird)
        try await settle(store)
        XCTAssertEqual(publications.count, 1)
        store.setHeadHasEyelids(true)
        try await settle(store)
        store.setHeadHasEyelids(true)
        try await settle(store)
        let expected = try source.applying(.setRigType(.bird)).applying(.setHeadHasEyelids(true))
        XCTAssertEqual(store.snapshot?.document.encoded(), expected.encoded())
        XCTAssertEqual(publications.count, 2)
        let requests = await preview.requests
        XCTAssertEqual(requests, 1, "Stored intent must not enqueue geometry or rig evaluation")
        XCTAssertEqual(store.previewRevision, previewRevision)
        XCTAssertEqual(store.materialViewportRevision, materialRevision)
        XCTAssertEqual(store.mesh?.vertices.map(\.position), positions)
        XCTAssertEqual(store.cameraReset, camera)
        XCTAssertEqual(store.snapshot?.selectedIDs, [nodeID])
        XCTAssertEqual(store.locks, [.radius])
        XCTAssertEqual(store.snapshot?.document.asset(named: "opaque.bin"), Data([0, 255, 10, 128]))
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), try source.applying(.setRigType(.bird)).encoded())
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), source.encoded())
        store.redo()
        try await settle(store)
        store.redo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), expected.encoded())
        let reopened = EditorStore()
        defer { reopened.stop() }
        await reopened.load(data: expected.encoded())
        try await settle(reopened)
        XCTAssertEqual(reopened.snapshot?.rigSettings, try expected.rigSettings())
        XCTAssertFalse(reopened.canUndo)
        store.stop()
        XCTAssertFalse(store.canEditRigSettings)
        store.setRigType(.fish)
        store.setHeadHasEyelids(false)
        XCTAssertEqual(store.snapshot?.document.encoded(), expected.encoded())
    }

    @MainActor func testEyelidOnlyEditPreservesUnsupportedTemplateAndOtherWindow() async throws {
        let source = try document()
        let first = EditorStore()
        let second = EditorStore()
        defer {
            first.stop()
            second.stop()
        }
        await first.load(data: source.encoded())
        await second.load(data: source.encoded())
        try await settle(first)
        try await settle(second)
        first.setHeadHasEyelids(true)
        try await settle(first)
        XCTAssertEqual(first.snapshot?.rigSettings.sourceRigType, "future")
        XCTAssertNil(first.snapshot?.rigSettings.rigType)
        XCTAssertEqual(first.snapshot?.document.encoded(), try source.applying(.setHeadHasEyelids(true)).encoded())
        XCTAssertEqual(second.snapshot?.document.encoded(), source.encoded())
        XCTAssertFalse(second.canUndo)
        first.undo()
        try await settle(first)
        XCTAssertEqual(first.snapshot?.document.encoded(), source.encoded())
    }

    @MainActor func testRigDisclosureRendersRecognizedUnsupportedUnloadedAndStoppedWithoutMutating() async throws {
        let store = EditorStore()
        defer { store.stop() }
        let source = try document()
        for state in ["unloaded", "unsupported", "recognized", "stopped"] {
            if state == "unsupported" {
                await store.load(data: source.encoded())
                try await settle(store)
            }
            if state == "recognized" {
                store.setRigType(.bird)
                try await settle(store)
                store.setHeadHasEyelids(true)
                try await settle(store)
            }
            if state == "stopped" { store.stop() }
            let before = store.snapshot?.document.encoded()
            let revision = store.snapshot?.documentRevision
            for scheme in [ColorScheme.light, .dark] {
                for expanded in [false, true] {
                    let png = try InspectorRenderer.png(
                        RigSettingsControls(store: store, isExpanded: expanded), width: 250, scheme: scheme)
                    XCTAssertNotNil(NSBitmapImageRep(data: png))
                    if let output = ProcessInfo.processInfo.environment["DUST3D_UI_QA_OUTPUT_DIR"] {
                        let directory = URL(fileURLWithPath: output)
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        try png.write(
                            to: directory.appendingPathComponent(
                                "rig-\(state)-\(expanded ? "expanded" : "collapsed")-\(scheme == .dark ? "dark" : "light").png"
                            ),
                            options: .atomic)
                    }
                }
            }
            XCTAssertEqual(store.snapshot?.document.encoded(), before)
            XCTAssertEqual(store.snapshot?.documentRevision, revision)
        }
    }
}

private actor CountingRigPreview: EditorPreviewServing {
    private let service = EditorPreviewService()
    private(set) var requests = 0
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult {
        requests += 1
        return try await service.generate(data, scopeID: scopeID)
    }
    func reset(scopeID: UUID) async throws { try await service.reset(scopeID: scopeID) }
}
