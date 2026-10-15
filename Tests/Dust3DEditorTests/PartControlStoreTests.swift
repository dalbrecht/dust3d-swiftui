import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

@testable import Dust3DEditor

final class PartControlStoreTests: XCTestCase {
    @MainActor
    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isGenerating { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Part operation or mesh generation did not settle")
    }
    @MainActor
    func testPartControlsRetainSelectionAndHandleAllDisabledAsEmpty() async throws {
        let partID = "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}"
        let original = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(
                id: "{11111111-1111-4111-8111-111111111111}", partID: partID,
                componentID: "{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}", position: .init(x: 0.5, y: 0.5, z: 0.5),
                radius: 0.1))
        let store = EditorStore()
        defer { store.stop() }
        await store.load(data: original.encoded())
        try await settle(store)
        XCTAssertEqual(store.mesh?.triangleCount, 16)
        store.selectPart(partID)
        try await settle(store)
        store.setPartState(partID, property: .visible, value: false)
        try await settle(store)
        XCTAssertEqual(store.mesh?.triangleCount, 16)
        XCTAssertTrue(store.snapshot?.nodes.allSatisfy { !$0.isVisible && !$0.isEditable } == true)
        store.setPartState(partID, property: .locked, value: true)
        try await settle(store)
        XCTAssertEqual(store.mesh?.triangleCount, 16)
        store.setPartState(partID, property: .disabled, value: true)
        try await settle(store)
        XCTAssertNil(store.mesh)
        XCTAssertNil(store.previewState.errorMessage)
        XCTAssertFalse(store.previewState.isStale)
        XCTAssertEqual(store.snapshot?.selectedPartID, partID)
        store.setPartState(partID, property: .disabled, value: false)
        try await settle(store)
        XCTAssertEqual(store.mesh?.triangleCount, 16)
        store.undo()
        try await settle(store)
        XCTAssertNil(store.mesh)
        store.redo()
        try await settle(store)
        XCTAssertEqual(store.mesh?.triangleCount, 16)
        store.renamePart(partID, name: "Body & head")
        try await settle(store)
        XCTAssertEqual(store.snapshot?.selectedPart?.name, "Body & head")
        XCTAssertEqual(store.mesh?.triangleCount, 16)
        let saved = store.snapshot?.document.encoded()
        store.renamePart(partID, name: "bad\0name")
        try await settle(store)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(store.snapshot?.document.encoded(), saved)
    }
    @MainActor
    func testShowingOutlyingPartsRefitsAfterFlagsUndoAndRedoButNotMovement() async throws {
        let near = "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}"
        let far = "{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}"
        var document = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        for (node, part, component, x) in [
            ("{11111111-1111-4111-8111-111111111111}", near, "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}", 0.5),
            ("{22222222-2222-4222-8222-222222222222}", far, "{dddddddd-dddd-4ddd-8ddd-dddddddddddd}", 20.0),
        ] {
            document = try document.applying(
                .addNode(id: node, partID: part, componentID: component, position: .init(x: x, y: x, z: x), radius: 0.1)
            )
        }
        for property in [PartStateProperty.visible, .disabled] {
            let inactive = property == .disabled
            let original = try document.applying(.setPartState(id: far, property: property, value: inactive))
            let store = EditorStore()
            await store.load(data: original.encoded())
            try await settle(store)
            let initialReset = store.cameraReset
            store.setPartState(far, property: property, value: !inactive)
            try await settle(store)
            XCTAssertEqual(store.cameraReset, initialReset, "Overlay changes must preserve the mesh orbit")
            func assertFarNodeFits(file: StaticString = #filePath, line: UInt = #line) {
                for plane in EditingPlane.allCases {
                    let point = CanvasProjection(bounds: store.bounds, plane: plane, width: 600, height: 400)
                        .point(for: .init(x: 20, y: 20, z: 20))
                    XCTAssertTrue((0...600).contains(point.x), file: file, line: line)
                    XCTAssertTrue((0...400).contains(point.y), file: file, line: line)
                }
            }
            assertFarNodeFits()
            let shownReset = store.cameraReset
            store.undo()
            try await settle(store)
            XCTAssertEqual(store.cameraReset, shownReset)
            store.fit()
            let hiddenReset = store.cameraReset
            store.redo()
            try await settle(store)
            XCTAssertEqual(store.cameraReset, hiddenReset)
            assertFarNodeFits()
            let fitted = store.cameraReset
            store.move(id: "{22222222-2222-4222-8222-222222222222}", to: .init(x: 21, y: 20, z: 20))
            try await settle(store)
            XCTAssertEqual(store.cameraReset, fitted, "Movement must keep the drag coordinate system stable")
            store.stop()
        }
    }

}
