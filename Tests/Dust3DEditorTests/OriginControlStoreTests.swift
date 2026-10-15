import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

@testable import Dust3DEditor

final class OriginControlStoreTests: XCTestCase {
    @MainActor
    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Origin operation did not settle")
    }
    @MainActor
    func testOriginControlInputRegenerationLocksUndoAndFailures() async throws {
        let original = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(
                id: "{11111111-1111-4111-8111-111111111111}", partID: "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}",
                componentID: "{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}", position: .init(x: 0.5, y: 0.5, z: 0.5),
                radius: 0.1))
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: original.encoded())
        try await settle(store)
        let revision = store.previewRevision
        store.setOrigin(x: "1", y: "2", z: "3")
        try await settle(store)
        XCTAssertEqual(store.snapshot?.origin, .init(x: 1, y: 2, z: 3))
        XCTAssertEqual(store.mesh?.triangleCount, 16)
        XCTAssertGreaterThan(store.previewRevision, revision)
        store.setLock(.x, isLocked: true)
        try await settle(store)
        store.setOrigin(x: "9", y: "4", z: "5")
        try await settle(store)
        XCTAssertEqual(store.snapshot?.origin, .init(x: 1, y: 4, z: 5))
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.origin, .init(x: 1, y: 2, z: 3))
        let before = store.snapshot?.document.encoded()
        for value in ["", "oops", "nan", "inf", "1000001"] {
            store.setOrigin(x: value, y: "0", z: "0")
            try await settle(store)
            XCTAssertNotNil(store.errorMessage)
            XCTAssertEqual(store.snapshot?.document.encoded(), before)
            XCTAssertTrue(store.canRedo)
        }
        store.redo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.origin, .init(x: 1, y: 4, z: 5))
        let node = try XCTUnwrap(store.snapshot?.nodes.first)
        XCTAssertEqual(node.value, try original.node(id: node.id))
        store.stop()
        store.setOrigin(x: "bad", y: "0", z: "0")
        XCTAssertNil(store.errorMessage)
    }
    @MainActor
    func testInitializingUnavailableOriginRecoversPinnedCorePreviewAndIsUndoable() async throws {
        let original = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(
                id: "{11111111-1111-4111-8111-111111111111}", partID: "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}",
                componentID: "{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}", position: .init(x: 0.5, y: 0.5, z: 1),
                radius: 0.1))
        let xml = try XMLDocument(data: original.modelXML)
        for key in ["originX", "originY", "originZ"] { xml.rootElement()?.removeAttribute(forName: key) }
        let model = xml.xmlData(options: [.nodePreserveAll])
        let header = "<ds3><model name='model.xml' offset='0' size='\(model.count)'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        let data =
            Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
            + model
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: data)
        try await settle(store)
        XCTAssertNil(store.snapshot?.origin)
        XCTAssertNotNil(store.previewState.errorMessage)
        store.setOrigin(x: "0.5", y: "0.5", z: "1")
        try await settle(store)
        XCTAssertEqual(store.mesh?.triangleCount, 16)
        XCTAssertNil(store.previewState.errorMessage)
        XCTAssertFalse(store.previewState.isStale)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), data)
        XCTAssertNotNil(store.previewState.errorMessage)
        XCTAssertTrue(store.previewState.isStale)
        store.redo()
        try await settle(store)
        XCTAssertEqual(store.mesh?.triangleCount, 16)
        XCTAssertNil(store.previewState.errorMessage)
    }

    @MainActor
    func testOriginChangesRefitCanvasWithoutResettingMeshCamera() async throws {
        let original = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(
                id: "{11111111-1111-4111-8111-111111111111}", partID: "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}",
                componentID: "{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}", position: .init(x: 0.5, y: 0.5, z: 1),
                radius: 0.1))
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: original.encoded())
        try await settle(store)
        let camera = store.cameraReset
        func assertOriginFits(file: StaticString = #filePath, line: UInt = #line) throws {
            let origin = try XCTUnwrap(store.snapshot?.origin)
            for plane in EditingPlane.allCases {
                let point = CanvasProjection(bounds: store.bounds, plane: plane, width: 600, height: 400).point(
                    for: origin)
                XCTAssertTrue((0...600).contains(point.x), file: file, line: line)
                XCTAssertTrue((0...400).contains(point.y), file: file, line: line)
            }
        }
        store.setOrigin(x: "5", y: "-4", z: "7")
        try await settle(store)
        try assertOriginFits()
        XCTAssertEqual(store.cameraReset, camera)
        store.undo()
        try await settle(store)
        try assertOriginFits()
        XCTAssertEqual(store.cameraReset, camera)
        XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
        store.redo()
        try await settle(store)
        try assertOriginFits()
        XCTAssertEqual(store.cameraReset, camera)
        let saved = store.snapshot?.document.encoded()
        store.fit()
        XCTAssertEqual(store.cameraReset, camera + 1)
        XCTAssertEqual(store.snapshot?.document.encoded(), saved)
    }

}
