import Dust3DDocument
import Dust3DEditorModel
import XCTest

final class PartProfileOptionsTests: XCTestCase {
    private let owner = "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}"
    private let first = "{BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB}"
    private let second = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"

    private func document() throws -> Dust3DDocument {
        var document = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        for (index, id) in [owner, "legacy", first, second].enumerated() {
            document = try document.applying(
                .addNode(
                    id: "n\(index)", partID: id, componentID: "c\(index)",
                    position: .init(x: Double(index), y: 0, z: 0), radius: 0.1))
            document = try document.applying(.setPartName(id: id, name: "Duplicate Curve 曲線"))
        }
        return document
    }

    func testCandidatesExcludeLegacyIdentitiesAndSelfWithoutRewritingSource() throws {
        let document = try document()
        let parts = try document.editorContents().parts
        let before = document.encoded()
        XCTAssertEqual(parts.map(\.canBeCutFaceProfile), [true, false, true, true])
        XCTAssertEqual(
            PartProfileOptions.candidates(in: parts, excluding: owner, matching: "").map(\.id), [first, second])
        XCTAssertEqual(document.encoded(), before)
        XCTAssertEqual(
            try Dust3DDocument(data: before).editorContents().parts.map(\.id), [owner, "legacy", first, second])
    }

    func testQtProfileInventoryIncludesDedicatedAndPreviouslyLinkedPartsInFrontOrder() throws {
        let unlinked = "{dddddddd-dddd-4ddd-8ddd-dddddddddddd}"
        let empty = "{eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee}"
        let unresolved = "{ffffffff-ffff-4fff-8fff-ffffffffffff}"
        let source = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes>
                <node id='r1' partId='\(first)' x='1' y='0' z='0' radius='.1'/>
                <node id='r2' partId='\(first)' x='3' y='0' z='0' radius='.1'/>
                <node id='l1' partId='\(second)' x='-4' y='0' z='0' radius='.1'/>
                <node id='l2' partId='\(second)' x='-2' y='0' z='0' radius='.1'/>
                </nodes><parts>
                <part id='\(owner)' cutFace='\(second)'/>
                <part id='\(first)' target='CutFace' name='Right profile' cutFace='\(unresolved)'/>
                <part id='\(unlinked)' name='Ordinary part'/>
                <part id='\(empty)' target='CutFace' name='Empty profile'/>
                <part id='\(second)' name='Left legacy profile'/>
                <part id='legacy' target='CutFace'/>
                </parts><components/></canvas>
                """.utf8))
        let snapshot = try EditorState(document: source).snapshot
        XCTAssertEqual(
            PartProfileOptions.candidates(in: snapshot, excluding: owner, matching: "").map(\.id),
            [second, empty, first])
        XCTAssertEqual(
            PartProfileOptions.candidates(in: snapshot, excluding: owner, matching: "legacy").map(\.id),
            [second])
        XCTAssertEqual(
            PartProfileOptions.candidates(in: snapshot, excluding: second, matching: "").map(\.id),
            [empty, first])
        XCTAssertEqual(snapshot.document.encoded(), source.encoded())
    }

    func testCyclePreflightMatchesPartAndNodeDependencyValidation() throws {
        let safe = "{dddddddd-dddd-4ddd-8ddd-dddddddddddd}"
        let peer = "{eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee}"
        let source = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes>
                <node id='dependent' partId='\(second)' cutFace='\(first)' x='1' y='0' z='0' radius='.1'/>
                </nodes><parts>
                <part id='\(owner)'/>
                <part id='\(first)' target='CutFace' cutFace='\(owner)'/>
                <part id='\(second)' target='CutFace'/>
                <part id='\(safe)' target='CutFace' cutFace='\(peer)'/>
                <part id='\(peer)' target='CutFace' cutFace='\(safe)'/>
                </parts><components/></canvas>
                """.utf8))
        let snapshot = try EditorState(document: source).snapshot
        let blocked = CutFaceLinks.cyclicChoices(from: owner, parts: snapshot.parts, nodes: snapshot.nodes)
        XCTAssertEqual(blocked, [first, second])
        for id in [first, second] {
            XCTAssertThrowsError(try source.applying(.setPartCutFace(id: owner, selection: .linkedPart(id)))) {
                XCTAssertEqual($0 as? DocumentError, .cyclicProfile)
            }
        }
        for id in [safe, peer] {
            XCTAssertNoThrow(try source.applying(.setPartCutFace(id: owner, selection: .linkedPart(id))))
        }
        XCTAssertEqual(snapshot.document.encoded(), source.encoded())
    }

    func testSearchMatchesTitlesAndExactSourceIdentityCaseInsensitivelyInSourceOrder() throws {
        let parts = try document().editorContents().parts
        for query in ["CURVE", "曲線", "duplicate"] {
            XCTAssertEqual(
                PartProfileOptions.candidates(in: parts, excluding: owner, matching: query).map(\.id), [first, second])
        }
        XCTAssertEqual(
            PartProfileOptions.candidates(in: parts, excluding: owner, matching: first.lowercased()).map(\.id), [first])
        XCTAssertEqual(PartProfileOptions.candidates(in: parts, excluding: owner, matching: "missing").map(\.id), [])
        XCTAssertEqual(PartProfileOptions.candidates(in: parts, excluding: owner, matching: "legacy").map(\.id), [])
        XCTAssertTrue(PartProfileOptions.candidates(in: [], excluding: owner, matching: "").isEmpty)
    }
}
