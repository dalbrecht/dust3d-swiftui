import Dust3DDocument
import Foundation
import XCTest

final class ClipboardPartitionTests: XCTestCase {
    private func fragment() throws -> NodeClipboard {
        let xml =
            "<canvas><nodes><node id='a' partId='p' x='0' y='0' z='0' radius='.1'/><node id='b' partId='p' x='1' y='0' z='0' radius='.1'/></nodes><parts><part id='p' locked='true' future='part'/></parts><components><component id='c' linkData='p' linkDataType='partId' color='#123456' future='style'/></components></canvas>"
        let model = Data(xml.utf8)
        let header = "<ds3><model name='model.xml' offset='0' size='\(model.count)'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        let source = try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model)
        return try source.copyingNodes(["a", "b"])
    }
    private func identities(_ fragment: NodeClipboard) -> [String: String] {
        Dictionary(uniqueKeysWithValues: fragment.identifiers.map { ($0, "new-\($0)") })
    }
    func testReadonlyPartitionsAreAllowedOnlyDuringFreshPasteConstruction() throws {
        let fragment = try fragment()
        XCTAssertThrowsError(try fragment.document.partSplitRequirements(for: ["p"]))
        let requirements = try fragment.partSplitRequirements()
        XCTAssertEqual(requirements.first?.additionalPartCount, 1)
        let original = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        let command = DocumentCommand.pasteNodes(
            clipboard: fragment, identities: identities(fragment), offset: .init(x: 0, y: 0, z: 0),
            partitions: ["new-p": [.init(partID: "new-p2", componentIDs: ["new-c2"])]])
        var history = DocumentHistory(document: original)
        try history.apply(command)
        let pasted = history.document
        XCTAssertEqual(Set(try pasted.editorContents().nodes.compactMap(\.partID)), ["new-p", "new-p2"])
        XCTAssertTrue(try pasted.editorContents().nodes.allSatisfy { !$0.isEditable })
        let root = try XMLDocument(data: pasted.modelXML).rootElement()
        XCTAssertTrue(
            root?.elements(forName: "parts").first?.elements(forName: "part").allSatisfy {
                $0.attribute(forName: "future")?.stringValue == "part"
            } == true)
        XCTAssertTrue(
            root?.elements(forName: "components").first?.elements(forName: "component").allSatisfy {
                $0.attribute(forName: "future")?.stringValue == "style"
            } == true)
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertFalse(history.canUndo)
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.document.encoded(), pasted.encoded())
    }
    func testPartitionPlansRejectExistingPartsCollisionsAliasesAndExcessiveIds() throws {
        let fragment = try fragment()
        let original = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(
                id: "original", partID: "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}", componentID: "original-component",
                position: .init(x: 3, y: 0, z: 0), radius: 0.1))
        let plans: [[String: [PartSplitIdentity]]] = [
            ["{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}": [.init(partID: "other", componentIDs: ["other-c"])]],
            ["new-p": [.init(partID: "new-a", componentIDs: ["other-c"])]],
            ["new-p": [.init(partID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", componentIDs: ["other-c"])]],
            ["new-p": [.init(partID: "other", componentIDs: ["new-c"])]],
            ["new-p": [.init(partID: "other", componentIDs: [])]],
        ]
        for plan in plans {
            var history = DocumentHistory(document: original)
            XCTAssertThrowsError(
                try history.apply(
                    .pasteNodes(
                        clipboard: fragment, identities: identities(fragment), offset: .init(x: 0, y: 0, z: 0),
                        partitions: plan)))
            XCTAssertEqual(history.document.encoded(), original.encoded())
            XCTAssertFalse(history.canUndo)
        }
        XCTAssertThrowsError(
            try original.applying(
                .pasteNodes(
                    clipboard: fragment, identities: identities(fragment), offset: .init(x: 0, y: 0, z: 0),
                    partitions: ["new-p": [.init(partID: "other", componentIDs: Array(repeating: "id", count: 20_000))]]
                ))
        ) { XCTAssertEqual($0 as? DocumentError, .limitExceeded) }
    }
}
