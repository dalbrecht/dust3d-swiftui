import Dust3DDocument
import Foundation
import XCTest

final class PartJoiningTests: XCTestCase {
    private func document(
        sourceForward: Bool = true, targetForward: Bool = true, children: Bool = false, locked: Bool = false
    ) throws -> Dust3DDocument {
        let xml = """
            <canvas><nodes><node id='a' partId='p' x='0' y='0' z='0' radius='.1'/><node id='b' partId='p' x='1' y='0' z='0' radius='.1'/>
            <node id='c' partId='q' x='2' y='0' z='0' radius='.1' future='node'/><node id='d' partId='q' x='3' y='0' z='0' radius='.1'/>
            <node id='e' partId='r' x='4' y='0' z='0' radius='.1' cutFace='q'/></nodes>
            <edges><edge id='ab' partId='p' from='\(sourceForward ? "a" : "b")' to='\(sourceForward ? "b" : "a")'/><edge id='cd' partId='q' from='\(targetForward ? "c" : "d")' to='\(targetForward ? "d" : "c")' future='edge'><future/></edge></edges>
            <parts><part id='p' deformWidth='1.2' future='source'/><part id='q' locked='\(locked)' deformWidth='.8' future='consumed'/><part id='r' cutFace='q' future='unrelated'/></parts>
            <components><component id='source' linkData='p' linkDataType='partId' color='#ff123456'/><component id='target' linkData='q' linkDataType='partId' future='style'>\(children ? "<component id='child' linkData='r' linkDataType='partId'/><future/>" : "")</component><component id='repeat' linkData='q' linkDataType='partId'/></components>
            <future><component id='opaque' linkData='q' linkDataType='partId'/></future></canvas>
            """
        return try archive(xml)
    }
    private func archive(_ xml: String) throws -> Dust3DDocument {
        let model = Data(xml.utf8)
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(model.count)'/><image name='opaque' offset='\(model.count)' size='2'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + Data([0, 255]))
    }
    func testEveryEndpointOrientationPreservesSourceStyleAndUnrelatedData() throws {
        for sourceForward in [false, true] {
            for targetForward in [false, true] {
                let source = try document(sourceForward: sourceForward, targetForward: targetForward)
                let joined = try source.applying(.joinNodes(id: "join", from: "a", to: "c"))
                let contents = try joined.editorContents()
                XCTAssertEqual(contents.nodes.map(\.partID), ["p", "p", "p", "p", "r"])
                XCTAssertEqual(contents.edges.first { $0.id == "join" }?.fromID, sourceForward ? "c" : "a")
                XCTAssertEqual(contents.edges.first { $0.id == "join" }?.toID, sourceForward ? "a" : "c")
                XCTAssertEqual(contents.edges.first { $0.id == "cd" }?.fromID, sourceForward ? "d" : "c")
                XCTAssertEqual(contents.edges.first { $0.id == "cd" }?.toID, sourceForward ? "c" : "d")
                let xml = try XMLDocument(data: joined.modelXML)
                XCTAssertTrue(try xml.nodes(forXPath: "/canvas/parts/part[@id='q']").isEmpty)
                XCTAssertEqual(
                    (try xml.nodes(forXPath: "/canvas/parts/part[@id='p']").first as? XMLElement)?.attribute(
                        forName: "deformWidth")?.stringValue, "1.2")
                XCTAssertEqual(
                    (try xml.nodes(forXPath: "/canvas/parts/part[@id='r']").first as? XMLElement)?.attribute(
                        forName: "cutFace")?.stringValue, "p")
                XCTAssertEqual(
                    (try xml.nodes(forXPath: "/canvas/nodes/node[@id='e']").first as? XMLElement)?.attribute(
                        forName: "cutFace")?.stringValue, "p")
                XCTAssertEqual(
                    (try xml.nodes(forXPath: "/canvas/nodes/node[@id='c']").first as? XMLElement)?.attribute(
                        forName: "future")?.stringValue, "node")
                XCTAssertEqual(
                    (try xml.nodes(forXPath: "/canvas/edges/edge[@id='cd']").first as? XMLElement)?.elements(
                        forName: "future"
                    ).count, 1)
                XCTAssertEqual(
                    (try xml.nodes(forXPath: "/canvas/future/component").first as? XMLElement)?.attribute(
                        forName: "linkData")?.stringValue, "q")
                XCTAssertEqual(try xml.nodes(forXPath: "/canvas/components/component").count, 1)
                XCTAssertEqual(joined.asset(named: "opaque"), Data([0, 255]))
                var history = DocumentHistory(document: source)
                try history.apply(.joinNodes(id: "join", from: "a", to: "c"))
                XCTAssertTrue(history.undo())
                XCTAssertEqual(history.document.encoded(), source.encoded())
                XCTAssertFalse(history.canUndo)
                XCTAssertTrue(history.redo())
                XCTAssertEqual(history.document.encoded(), joined.encoded())
            }
        }
    }
    func testTargetReferenceWithChildrenBecomesGroup() throws {
        let source = try document(children: true)
        let joined = try source.applying(.joinNodes(id: "join", from: "a", to: "c"))
        let xml = try XMLDocument(data: joined.modelXML)
        let group = try XCTUnwrap(
            try xml.nodes(forXPath: "/canvas/components/component[@id='target']").first as? XMLElement)
        XCTAssertNil(group.attribute(forName: "linkData"))
        XCTAssertNil(group.attribute(forName: "linkDataType"))
        XCTAssertEqual(group.attribute(forName: "future")?.stringValue, "style")
        XCTAssertEqual(group.elements(forName: "component").first?.attribute(forName: "id")?.stringValue, "child")
        XCTAssertEqual(group.elements(forName: "future").count, 1)
        XCTAssertTrue(try xml.nodes(forXPath: "/canvas/components/component[@id='repeat']").isEmpty)
    }
    func testInvalidConnectionsAreAtomicAndReadonlyPartsAreProtected() throws {
        let source = try document()
        for command: DocumentCommand in [
            .joinNodes(id: "", from: "a", to: "c"), .joinNodes(id: "ab", from: "a", to: "c"),
            .joinNodes(id: "join", from: "missing", to: "c"), .joinNodes(id: "join", from: "a", to: "a"),
            .joinNodes(id: "join", from: "a", to: "b"),
        ] {
            XCTAssertThrowsError(try source.applying(command))
        }
        XCTAssertThrowsError(try document(locked: true).applying(.joinNodes(id: "join", from: "a", to: "c")))
        let branched = try source.applying(
            .addNode(id: "f", partID: "p", componentID: nil, position: .init(x: 0, y: 1, z: 0), radius: 0.1)
        ).applying(.addEdge(id: "af", from: "a", to: "f"))
        XCTAssertThrowsError(try branched.applying(.joinNodes(id: "join", from: "a", to: "c")))
        let disconnected = try source.applying(.removeEdge(id: "cd"))
        XCTAssertThrowsError(try disconnected.applying(.joinNodes(id: "join", from: "a", to: "c")))
        let unassigned = try archive(
            "<canvas><nodes><node id='x' x='0' y='0' z='0' radius='.1'/><node id='y' x='1' y='0' z='0' radius='.1'/></nodes></canvas>"
        )
        XCTAssertThrowsError(try unassigned.applying(.joinNodes(id: "join", from: "x", to: "y")))
        XCTAssertEqual(try source.editorContents().nodes.count, 5)
    }
    func testSamePartLoopClosureAndNewNodeExtensionUseSourceOrientation() throws {
        var source = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        for (index, id) in ["a", "b", "c"].enumerated() {
            source = try source.applying(
                .addNode(
                    id: id, partID: "p", componentID: index == 0 ? "comp" : nil,
                    position: .init(x: Double(index), y: 0, z: 0), radius: 0.1))
        }
        source = try source.applying(.addEdge(id: "ab", from: "a", to: "b")).applying(
            .addEdge(id: "bc", from: "b", to: "c"))
        let loop = try source.applying(.joinNodes(id: "ca", from: "a", to: "c"))
        XCTAssertEqual(try loop.editorContents().edges.last?.fromID, "c")
        XCTAssertEqual(try loop.editorContents().edges.last?.toID, "a")
        source = try source.applying(
            .addNode(id: "new", partID: "p", componentID: nil, position: .init(x: -1, y: 0, z: 0), radius: 0.1))
        let extended = try source.applying(.joinNodes(id: "newa", from: "a", to: "new"))
        XCTAssertEqual(try extended.editorContents().edges.last?.fromID, "new")
        XCTAssertEqual(try extended.editorContents().edges.last?.toID, "a")
    }
    func testProfileCyclesAndBranchingTargetsAreRejected() throws {
        let original = try document()
        for (path, target) in [
            ("/canvas/parts/part[@id='p']", "q"), ("/canvas/parts/part[@id='p']", "r"),
            ("/canvas/nodes/node[@id='a']", "q"),
        ] {
            let xml = try XMLDocument(data: original.modelXML)
            let element = try XCTUnwrap(try xml.nodes(forXPath: path).first as? XMLElement)
            let attribute = XMLNode(kind: .attribute)
            attribute.name = "cutFace"
            attribute.stringValue = target
            element.addAttribute(attribute)
            let source = try archive(xml.xmlString(options: [.nodePreserveAll]))
            XCTAssertThrowsError(try source.applying(.joinNodes(id: "join", from: "a", to: "c"))) {
                XCTAssertEqual($0 as? DocumentError, .cyclicProfile)
            }
        }
        for partID in ["p", "q"] {
            var branched = original
            for id in ["f", "g"] {
                branched = try branched.applying(
                    .addNode(id: id, partID: partID, componentID: nil, position: .init(x: 0, y: 1, z: 0), radius: 0.1)
                ).applying(.addEdge(id: "edge-\(id)", from: partID == "p" ? "b" : "d", to: id))
            }
            XCTAssertThrowsError(try branched.applying(.joinNodes(id: "join", from: "a", to: "c")))
        }
    }

    func testNamespaceAndExtensionTagsStayUntouchedWhenJoining() throws {
        let original = try document(children: true)
        let xml = try XMLDocument(data: original.modelXML)
        let namespace = XMLNode(kind: .namespace)
        namespace.name = ""
        namespace.stringValue = "urn:future"
        xml.rootElement()?.addNamespace(namespace)
        let source = try archive(xml.xmlString(options: [.nodePreserveAll]))
        let joined = try source.applying(.joinNodes(id: "join", from: "a", to: "c"))
        let result = try XMLDocument(data: joined.modelXML)
        XCTAssertEqual(result.rootElement()?.uri, "urn:future")
        let opaque = result.rootElement()?.elements(forName: "future").first?.elements(forName: "component").first
        XCTAssertEqual(opaque?.attribute(forName: "linkData")?.stringValue, "q")
        XCTAssertEqual(try joined.editorContents().nodes.filter { $0.partID == "p" }.count, 4)
    }

}
