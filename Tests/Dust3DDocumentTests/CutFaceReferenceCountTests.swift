import Dust3DDocument
import Foundation
import XCTest

final class CutFaceReferenceCountTests: XCTestCase {
    private let profile = "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}"
    private let otherProfile = "{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}"
    private let nonProfile = "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}"
    private let missing = "{dddddddd-dddd-4ddd-8ddd-dddddddddddd}"

    func testCountsExactStoredPartAndOwnedNodeReferencesRegardlessOfVisibility() throws {
        let bareProfile = profile.dropFirst().dropLast()
        let xml = """
            <canvas future='keep'><nodes>
            <node id='n1' partId='owner' x='0' y='0' z='0' radius='.1' cutFace='\(profile)'/>
            <node id='n2' partId='owner' x='1' y='0' z='0' radius='.1' cutFace='\(profile)'/>
            <node id='unowned' x='0' y='0' z='0' radius='.1' cutFace='\(profile)'/>
            <node id='preset' partId='owner' x='0' y='0' z='0' radius='.1' cutFace='Hexagon'/>
            <node id='alias' partId='owner' x='0' y='0' z='0' radius='.1' cutFace='\(bareProfile)'/>
            <node id='dangling' partId='owner' x='0' y='0' z='0' radius='.1' cutFace='\(missing)'/>
            <node id='wrong-role' partId='owner' x='0' y='0' z='0' radius='.1' cutFace='\(nonProfile)'/>
            </nodes><parts>
            <part id='owner' visible='false' disabled='true' cutFace='\(profile)'/>
            <part id='\(profile)' target='CutFace' visible='false'/>
            <part id='\(otherProfile)' target='CutFace'/>
            <part id='\(nonProfile)' target='Model'/>
            </parts></canvas>
            """
        let model = Data(xml.utf8)
        let source = try Dust3DDocument(snapshotXML: model)
        let archive = source.encoded()
        let parts = try source.editorContents().parts

        XCTAssertEqual(parts.first { $0.id == profile }?.cutFaceReferenceCount, 3)
        XCTAssertEqual(parts.first { $0.id == otherProfile }?.cutFaceReferenceCount, 0)
        XCTAssertEqual(parts.first { $0.id == nonProfile }?.cutFaceReferenceCount, 0)
        XCTAssertEqual(source.modelXML, model)
        XCTAssertEqual(source.encoded(), archive)
    }

    func testCanonicallyEquivalentButByteDifferentLinkIsNotResolved() throws {
        let exact = "{\u{00E9}aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}"
        let otherSpelling = "{e\u{0301}aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}"
        XCTAssertEqual(exact, otherSpelling)
        let xml = """
            <canvas><parts>
            <part id='owner' cutFace='\(otherSpelling)'/>
            <part id='\(exact)' target='CutFace'/>
            </parts></canvas>
            """
        let document = try Dust3DDocument(snapshotXML: Data(xml.utf8))
        let part = try XCTUnwrap(document.editorContents().parts.first { $0.id == exact })
        XCTAssertEqual(part.cutFaceReferenceCount, 0)
    }

    func testReferenceCountChangesAfterLinkEditAndUndoRestoresSource() throws {
        let xml = """
            <canvas><parts>
            <part id='owner' cutFace='\(profile)'/>
            <part id='\(profile)' target='CutFace'/>
            </parts></canvas>
            """
        let source = try Dust3DDocument(snapshotXML: Data(xml.utf8))
        var history = DocumentHistory(document: source)
        XCTAssertEqual(try count(in: history.document), 1)

        try history.apply(.setPartCutFace(id: "owner", selection: .preset(.triangle)))
        XCTAssertEqual(try count(in: history.document), 0)
        XCTAssertTrue(history.undo())
        XCTAssertEqual(try count(in: history.document), 1)
        XCTAssertEqual(history.document.encoded(), source.encoded())
    }

    private func count(in document: Dust3DDocument) throws -> Int {
        let part = try XCTUnwrap(document.editorContents().parts.first { $0.id == profile })
        return part.cutFaceReferenceCount
    }
}
