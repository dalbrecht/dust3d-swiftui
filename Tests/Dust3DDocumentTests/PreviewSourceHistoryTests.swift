import XCTest

@testable import Dust3DDocument

final class PreviewSourceHistoryTests: XCTestCase {
    func testMaterialOnlyChangesHaveIndependentHistoryIdentity() throws {
        let part = "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}"
        let document = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(
                id: "{11111111-1111-4111-8111-111111111111}", partID: part,
                componentID: "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}",
                position: .init(x: 0, y: 0, z: 0), radius: 0.1))
        var history = DocumentHistory(document: document)
        let initial = history.previewIdentity
        try history.apply(.setPartMaterial(id: part, property: .roughness, value: 0.25))
        let material = history.previewIdentity
        XCTAssertEqual(material.geometry, initial.geometry)
        XCTAssertNotEqual(material.materials, initial.materials)
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.previewIdentity, initial)
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.previewIdentity, material)
        try history.apply(.setPartMaterial(id: part, property: .roughness, value: 0.25))
        XCTAssertEqual(history.previewIdentity, material, "Semantic no-ops retain identities")
        XCTAssertThrowsError(try history.apply(.setPartMaterial(id: part, property: .roughness, value: -1)))
        XCTAssertEqual(history.previewIdentity, material, "Rejected commands retain identities")
        try history.apply(.setPartState(id: part, property: .visible, value: false))
        XCTAssertEqual(history.previewIdentity, material)
        try history.apply(.setPartState(id: part, property: .disabled, value: true))
        XCTAssertNotEqual(history.previewIdentity.geometry, material.geometry)
    }

    func testAnimationHistoryRetainsPreviewIdentityWhileDocumentBytesChange() throws {
        var history = try DocumentHistory(document: Dust3DDocument(data: Dust3DDocument.emptyArchive()))
        let initial = history.previewIdentity
        let bytes = history.document.encoded()
        try history.apply(.createAnimation(id: "walk", name: "Walk", type: "walk"))
        XCTAssertNotEqual(history.document.encoded(), bytes)
        XCTAssertEqual(history.previewIdentity, initial)
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), bytes)
        XCTAssertEqual(history.previewIdentity, initial)
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.previewIdentity, initial)
    }

    func testGeometryHistoryRestoresItsOriginalSourceIdentity() throws {
        var history = try DocumentHistory(document: Dust3DDocument(data: Dust3DDocument.emptyArchive()))
        let initial = history.previewIdentity
        try history.apply(.setOrigin(.init(x: 1, y: 2, z: 3)))
        let edited = history.previewIdentity
        XCTAssertNotEqual(edited.geometry, initial.geometry)
        XCTAssertNotEqual(edited.materials, initial.materials)
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.previewIdentity, initial)
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.previewIdentity, edited)
    }

    func testCancelledAndNetZeroTransactionsRestoreIdentityAndBytes() throws {
        var history = try DocumentHistory(document: Dust3DDocument(data: Dust3DDocument.emptyArchive()))
        let initial = history.previewIdentity
        let bytes = history.document.encoded()
        try history.beginTransaction()
        try history.apply(.setOrigin(.init(x: 1, y: 2, z: 3)))
        history.cancelTransaction()
        XCTAssertEqual(history.previewIdentity, initial)
        XCTAssertEqual(history.document.encoded(), bytes)
        try history.beginTransaction()
        try history.apply(.createAnimation(id: "walk", name: "Walk", type: "walk"))
        try history.apply(.deleteAnimation(id: "walk"))
        try history.endTransaction()
        XCTAssertEqual(history.previewIdentity, initial)
        XCTAssertEqual(history.document.encoded(), bytes)
        XCTAssertFalse(history.canUndo)
    }

    func testFreshHistoryWithIdenticalBytesHasIndependentPreviewIdentity() throws {
        let document = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        XCTAssertNotEqual(
            DocumentHistory(document: document).previewIdentity, DocumentHistory(document: document).previewIdentity)
    }
}
