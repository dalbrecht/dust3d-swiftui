import Dust3DDocument
import Foundation
import XCTest

final class ComponentMeshBatchTests: XCTestCase {
    private func source() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                "<canvas future='keep'><nodes/><edges/><parts/><components><component id='a' inverse='True' smoothCutoffDegrees='090.00' future='keep'><component id='child' linkDataType='future' linkData='opaque'/><!--keep--></component><component id='b' combineMode='Future' smoothCutoffDegrees='future' linkDataType='partId' linkData='missing'/></components></canvas>"
                    .utf8))
    }
    func testBatchPreservesNoopSpellingsAndChangesOnlySelectedFieldWithOneExactUndo() throws {
        let original = try source()
        var history = DocumentHistory(document: original)
        try history.apply(.editComponentMeshSettings(ids: ["a", "b", "a"], edit: .combineMode(.inversion)))
        XCTAssertEqual(try history.document.components().prefix(1).first?.combineMode, .inversion)
        let xml = String(decoding: history.document.modelXML, as: UTF8.self)
        XCTAssertTrue(xml.contains("inverse='True'"))
        XCTAssertTrue(xml.contains("smoothCutoffDegrees='090.00'"))
        XCTAssertTrue(xml.contains("<!--keep-->"))
        XCTAssertEqual(try history.document.components().last?.combineMode, .inversion)
        history.undo()
        XCTAssertEqual(history.document.encoded(), original.encoded())
        try history.apply(.editComponentMeshSettings(ids: ["a"], edit: .combineMode(.inversion)))
        XCTAssertTrue(history.canRedo)
        history.redo()
        try history.apply(.editComponentMeshSettings(ids: ["a", "b"], edit: .smoothCutoffDegrees(0)))
        XCTAssertEqual(try history.document.components().first?.smoothCutoffDegrees, 0)
        XCTAssertEqual(try history.document.components().last?.smoothCutoffDegrees, 0)
        XCTAssertFalse(String(decoding: history.document.modelXML, as: UTF8.self).contains("smoothCutoffDegrees="))
    }
    func testEveryExactRequestValidatedBeforeDedupAndInvalidBatchIsAtomic() throws {
        let nfd = "cafe\u{301}"
        let nfc = "caf\u{e9}"
        let original = try Dust3DDocument(
            snapshotXML: Data("<canvas><components><component id='\(nfd)'/></components></canvas>".utf8))
        for ids in [[nfd, nfc], [nfc, nfd]] {
            XCTAssertThrowsError(
                try original.applying(.editComponentMeshSettings(ids: ids, edit: .combineMode(.normal)))
            ) {
                guard case .missingComponent(let id) = $0 as? DocumentError else { return XCTFail("Original error") }
                XCTAssertEqual(Array(id.utf8), Array(nfc.utf8))
            }
        }
        XCTAssertEqual(
            try original.applying(.editComponentMeshSettings(ids: [], edit: .smoothCutoffDegrees(.nan))).encoded(),
            original.encoded())
        XCTAssertThrowsError(
            try original.applying(
                .editComponentMeshSettings(
                    ids: Array(repeating: nfd, count: ComponentMeshEdit.maximumBatchCount + 1),
                    edit: .combineMode(.normal)))
        ) {
            XCTAssertEqual($0 as? DocumentError, .limitExceeded)
        }
        for value: Double in [-1, 181, .nan, .infinity] {
            XCTAssertThrowsError(
                try original.applying(.editComponentMeshSettings(ids: [nfd], edit: .smoothCutoffDegrees(value))))
        }
        XCTAssertEqual(try original.components().first?.combineMode, .normal)
        XCTAssertEqual(
            try original.applying(.editComponentMeshSettings(ids: [], edit: .combineMode(.inversion))).encoded(),
            original.encoded())
    }
    func testOpaqueLinksAndExplicitNestedRowsAreMetadataEligibleAndNoopsPreserveRedo() throws {
        let original = try source()
        let edited = try original.applying(
            .editComponentMeshSettings(ids: ["a", "child", "b"], edit: .combineMode(.normal)))
        XCTAssertTrue(try edited.components().allSatisfy { $0.combineMode == .normal })
        XCTAssertEqual(try edited.components().first?.childIDs, ["child"])
        XCTAssertEqual(try edited.components().last?.linkData, "missing")
        XCTAssertEqual(try edited.components().first?.smoothCutoffDegrees, 90)
        var history = DocumentHistory(document: edited)
        try history.apply(.editComponentMeshSettings(ids: ["a"], edit: .smoothCutoffDegrees(180)))
        history.undo()
        try history.apply(.editComponentMeshSettings(ids: ["a"], edit: .smoothCutoffDegrees(90)))
        XCTAssertTrue(history.canRedo)
        XCTAssertEqual(history.document.encoded(), edited.encoded())
    }
    func testRoleBearingLockedOwnersAssetsMixedNoopAndUnselectedChildrenStayLossless() throws {
        let roles = ["Model", "ImportedModel", "CutFace", "StitchingLine", "StitchingLoop", "Future"]
        let parts = roles.enumerated().map {
            "<part id='p\($0.offset)' target='\($0.element)' locked='true' disabled='true' visible='false' future='keep'/>"
        }.joined()
        let leaves = roles.indices.map {
            "<component id='r\($0)' linkDataType='partId' linkData='p\($0)' smoothCutoffDegrees='\($0 == 0 ? "090.00" : "future")'/>"
        }.joined()
        let xml = Data(
            "<canvas future='keep'><nodes/><edges/><parts>\(parts)</parts><components><component id='root'>\(leaves)<component id='unselected' smoothCutoffDegrees='017.00'/></component></components></canvas>"
                .utf8)
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(xml.count)'/><asset name='opaque.bin' offset='\(xml.count)' size='4'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        let original = try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + xml + Data([0, 255, 10, 128]))
        var history = DocumentHistory(document: original)
        let before = history.previewIdentity
        try history.apply(
            .editComponentMeshSettings(ids: ["root"] + roles.indices.map { "r\($0)" }, edit: .smoothCutoffDegrees(90)))
        XCTAssertNotEqual(before.geometry, history.previewIdentity.geometry)
        XCTAssertNotEqual(before.materials, history.previewIdentity.materials)
        XCTAssertEqual(try history.document.editorContents().parts, try original.editorContents().parts)
        XCTAssertEqual(history.document.asset(named: "opaque.bin"), original.asset(named: "opaque.bin"))
        let result = try XMLDocument(data: history.document.modelXML)
        let rows = try result.nodes(forXPath: "//component").compactMap { $0 as? XMLElement }
        XCTAssertEqual(
            rows.first { $0.attribute(forName: "id")?.stringValue == "r0" }?.attribute(forName: "smoothCutoffDegrees")?
                .stringValue, "090.00")
        XCTAssertEqual(
            rows.first { $0.attribute(forName: "id")?.stringValue == "unselected" }?.attribute(
                forName: "smoothCutoffDegrees")?.stringValue, "017.00")
        XCTAssertEqual(
            try history.document.components().filter { $0.id.hasPrefix("r") }.map(\.smoothCutoffDegrees),
            Array(repeating: 90, count: 7))
        history.undo()
        XCTAssertTrue(history.document.hasSameEditingState(as: original))
    }

    func testCancelledDirectBatchNeverPublishesItsOwnedDOM() async throws {
        let original = try source()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try original.applying(.editComponentMeshSettings(ids: ["a", "b"], edit: .combineMode(.normal)))
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled batch")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try original.components().first?.combineMode, .inversion)
        XCTAssertEqual(try original.components().last?.combineMode, nil)
    }

}
