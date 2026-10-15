import Dust3DDocument
import Foundation
import XCTest

final class TopologyTests: XCTestCase {
    private func seed() throws -> Dust3DDocument {
        try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(id: "a", partID: "p", componentID: "c", position: .init(x: 0, y: 0, z: 0), radius: 0.1))
    }

    func testCreateConnectDeleteAndUndoRestoreExactArchives() throws {
        let empty = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        var history = DocumentHistory(document: empty)
        try history.apply(
            .addNode(id: "a", partID: "p", componentID: "c", position: .init(x: 0, y: 0, z: 0), radius: 0.1))
        let first = history.document.encoded()
        try history.apply(
            .addNode(id: "b", partID: "p", componentID: nil, position: .init(x: 0, y: 1, z: 0), radius: 0.2))
        try history.apply(.addEdge(id: "e", from: "a", to: "b"))
        let connected = history.document.encoded()
        XCTAssertEqual(try history.document.editorContents().edges.count, 1)
        try history.apply(.removeNode(id: "a"))
        XCTAssertTrue(try history.document.editorContents().edges.isEmpty)
        XCTAssertEqual(try history.document.editorContents().nodes.map(\.id), ["b"])
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), connected)
        try history.apply(.removeEdge(id: "e"))
        XCTAssertTrue(try history.document.editorContents().edges.isEmpty)
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), connected)
        XCTAssertTrue(history.redo())
        XCTAssertTrue(history.undo())
        XCTAssertTrue(history.undo())
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), first)
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), empty.encoded())
    }

    func testInvalidTopologyCommandsLeaveOriginalUntouched() throws {
        let original = try seed()
        let connected = try original.applying(
            .addNode(id: "b", partID: "p", componentID: nil, position: .init(x: 0, y: 1, z: 0), radius: 0.1)
        )
        .applying(.addEdge(id: "e", from: "a", to: "b"))
        let commands: [DocumentCommand] = [
            .addNode(id: "a", partID: "p", componentID: nil, position: .init(x: 0, y: 0, z: 0), radius: 1),
            .addNode(id: "bad", partID: "missing", componentID: nil, position: .init(x: 0, y: 0, z: 0), radius: 1),
            .addNode(id: "bad", partID: "p", componentID: nil, position: .init(x: .nan, y: 0, z: 0), radius: 1),
            .addEdge(id: "e2", from: "a", to: "a"), .addEdge(id: "e2", from: "b", to: "a"),
            .addEdge(id: "e", from: "a", to: "b"), .addEdge(id: "new", from: "a", to: "absent"),
            .removeNode(id: "absent"), .removeEdge(id: "absent"),
        ]
        for command in commands { XCTAssertThrowsError(try connected.applying(command)) }
        XCTAssertEqual(try connected.editorContents().nodes.count, 2)
        XCTAssertEqual(try connected.editorContents().edges.count, 1)
    }

    func testTopologyInsideTransactionCommitsAndCancelsAtomically() throws {
        var history = DocumentHistory(document: try seed())
        let before = history.document.encoded()
        try history.beginTransaction()
        try history.apply(
            .addNode(id: "b", partID: "p", componentID: nil, position: .init(x: 0, y: 1, z: 0), radius: 0.1))
        try history.apply(.addEdge(id: "e", from: "a", to: "b"))
        try history.endTransaction()
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), before)
        try history.beginTransaction()
        try history.apply(.removeNode(id: "a"))
        history.cancelTransaction()
        XCTAssertEqual(history.document.encoded(), before)
    }
    func testUnknownFieldsAssetsAndPartLocksSurviveTopologyEdits() throws {
        let xml =
            "<canvas future='keep'><nodes><node id='a' partId='p' x='0' y='0' z='0' radius='0.1' custom='preserve'/></nodes><parts><part id='p' locked='false' visible='true' future='retained'/></parts><components><component id='c' linkData='p' linkDataType='partId' future='retained'/></components><future><data>opaque</data></future></canvas>"
        func archive(_ xml: String) -> Data {
            let model = Data(xml.utf8)
            let header =
                "<ds3 custom='keep'><model name='model.xml' offset='0' size='\(model.count)'/><image name='opaque' offset='\(model.count)' size='4' future='keep'/></ds3>"
            let prefix = "DUST3D 1.0 xml "
            return Data(
                (prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + Data([0, 255, 1, 128])
        }
        let original = try Dust3DDocument(data: archive(xml))
        let added = try original.applying(
            .addNode(id: "b", partID: "p", componentID: nil, position: .init(x: 1, y: 0, z: 0), radius: 0.2))
        let connected = try added.applying(.addEdge(id: "e", from: "a", to: "b"))
        let edited = try connected.applying(.removeNode(id: "b"))
        let reopened = try Dust3DDocument(data: edited.encoded())
        XCTAssertEqual(reopened.asset(named: "opaque"), Data([0, 255, 1, 128]))
        let output = String(decoding: reopened.modelXML, as: UTF8.self)
        let parsed = try XMLDocument(data: reopened.modelXML)
        XCTAssertEqual((try parsed.nodes(forXPath: "/canvas/nodes/node/@custom")).first?.stringValue, "preserve")
        XCTAssertTrue(output.contains("<future><data>opaque</data></future>"))
        XCTAssertEqual((try parsed.nodes(forXPath: "/canvas/parts/part/@future")).first?.stringValue, "retained")
        for flag in ["locked='true' visible='true'", "locked='false' visible='false'"] {
            let locked = try Dust3DDocument(
                data: archive(xml.replacingOccurrences(of: "locked='false' visible='true'", with: flag)))
            XCTAssertThrowsError(
                try locked.applying(
                    .addNode(id: "b", partID: "p", componentID: nil, position: .init(x: 0, y: 0, z: 0), radius: 1)))
            XCTAssertThrowsError(try locked.applying(.removeNode(id: "a")))
        }
    }

}
