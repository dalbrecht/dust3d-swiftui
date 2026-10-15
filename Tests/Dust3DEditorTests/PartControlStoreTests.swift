import Dust3DDocument
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
}
