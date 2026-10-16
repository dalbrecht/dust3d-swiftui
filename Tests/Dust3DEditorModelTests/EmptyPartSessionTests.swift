import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class EmptyPartSessionTests: XCTestCase {
    private func document() throws -> Dust3DDocument {
        let model = Data(
            "<canvas originX='.5' originY='.5' originZ='1'><nodes><node id='a' partId='p' x='0' y='0' z='0' radius='.1'/><node id='b' partId='q' x='1' y='0' z='0' radius='.1'/></nodes><parts><part id='p' future='keep'/><part id='q'/><part id='template'/></parts><components><component id='pc' linkDataType='partId' linkData='p'/><component id='qc' linkDataType='partId' linkData='q'/><component id='tc' linkDataType='partId' linkData='template'/></components></canvas>"
                .utf8)
        let header = "<ds3><model name='model.xml' offset='0' size='\(model.count)'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model)
    }

    func testFinalNodeDeletionAndCutPruneOnlyAffectedPartInOneUndoStep() async throws {
        for cut in [false, true] {
            let original = try document()
            let session = EditorSession()
            _ = try await session.open(data: original.encoded())
            _ = try await session.select("a")
            if cut { _ = try await session.copyPayload(identifier: "cut") }
            let result = try await (cut ? session.deleteSelection() : session.apply([.removeNode(id: "a")]))
            XCTAssertEqual(result.nodes.map(\.id), ["b"])
            XCTAssertEqual(result.parts.map(\.id), ["q", "template"])
            XCTAssertNil(result.selectedID)
            let restored = try await session.undo()
            XCTAssertEqual(restored.document.encoded(), original.encoded())
            XCTAssertFalse(restored.canUndo)
            XCTAssertNil(restored.selectedID)
            let redone = try await session.redo()
            XCTAssertEqual(redone.document.encoded(), result.document.encoded())
        }
    }

    func testBatchRetainsRefilledPartAndPrunesPartSelectionWithoutRevivingOnUndo() async throws {
        let original = try document()
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        let replacement = try await session.apply([
            .removeNode(id: "a"),
            .addNode(id: "replacement", partID: "p", componentID: nil, position: .init(x: 2, y: 0, z: 0), radius: 0.1),
        ])
        XCTAssertEqual(replacement.parts.map(\.id), ["p", "q", "template"])
        XCTAssertTrue(String(decoding: replacement.document.modelXML, as: UTF8.self).contains("future='keep'"))
        _ = try await session.undo()
        _ = try await session.selectPart("p")
        let removed = try await session.apply([.removeNodes(["a", "b"])])
        XCTAssertEqual(removed.parts.map(\.id), ["template"])
        XCTAssertNil(removed.selectedPartID)
        XCTAssertFalse(removed.hasEnabledGeometry)
        let restored = try await session.undo()
        XCTAssertEqual(restored.document.encoded(), original.encoded())
        XCTAssertNil(restored.selectedPartID)
    }

    func testCleanupFailureRejectsEntireBatchAndExplicitCleanupDoesNotLeaveStaleAffectedIDs() async throws {
        let original = try document()
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        do {
            _ = try await session.apply([.removeNode(id: "a"), .setPartState(id: "p", property: .locked, value: true)])
            XCTFail("Readonly cleanup must reject atomically")
        } catch { XCTAssertEqual(error as? DocumentError, .invalidNode) }
        let unchanged = try await session.select(nil)
        XCTAssertEqual(unchanged.document.encoded(), original.encoded())
        XCTAssertFalse(unchanged.canUndo)
        let explicit = try await session.apply([.removeNode(id: "a"), .pruneEmptyParts(["p"])])
        XCTAssertEqual(explicit.parts.map(\.id), ["q", "template"])
    }
}
