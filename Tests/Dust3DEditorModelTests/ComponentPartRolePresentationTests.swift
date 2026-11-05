import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

final class ComponentPartRolePresentationTests: XCTestCase {
    func testCommonRoleForUniformMixedUnsupportedEmptyAndGroupOnlySelections() async throws {
        let xml = """
            <canvas><nodes/><edges/><parts>
            <part id='p'/><part id='q'/><part id='cut' target='CutFace'/><part id='future' target='Future'/>
            </parts><components>
            <component id='g'><component id='a' linkDataType='partId' linkData='p'/>
            <component id='b' linkDataType='partId' linkData='q'/></component>
            <component id='c' linkDataType='partId' linkData='cut'/>
            <component id='f' linkDataType='partId' linkData='future'/>
            <component id='missing' linkDataType='partId' linkData='absent'/>
            </components></canvas>
            """
        let session = EditorSession()
        let document = try Dust3DDocument(snapshotXML: Data(xml.utf8))
        _ = try await session.open(data: document.encoded())
        let cases: [(Set<String>, PartTarget?)] = [
            ([], nil), (["g"], nil), (["a", "b"], .model),
            (["g", "a"], .model), (["a", "c"], nil),
            (["c"], .cutFace), (["f"], nil), (["a", "f"], nil),
            (["a", "missing"], nil),
        ]
        for (ids, expected) in cases {
            let snapshot = try await session.selectComponents(ids)
            XCTAssertEqual(snapshot.selectedComponentPartRole, expected, "\(ids)")
            XCTAssertEqual(snapshot.document.encoded(), document.encoded())
            XCTAssertFalse(snapshot.canUndo)
        }
    }
    func testCommonRoleRequiresLiteralPartOwners() async throws {
        let xml = """
            <canvas><nodes/><edges/><parts><part id='cafe&#769;'/></parts><components>
            <component id='actual' linkDataType='partId' linkData='cafe&#769;'/>
            <component id='repeated' linkDataType='partId' linkData='cafe&#769;'/>
            <component id='alias' linkDataType='partId' linkData='caf&#233;'/>
            </components></canvas>
            """
        let session = EditorSession()
        let document = try Dust3DDocument(snapshotXML: Data(xml.utf8))
        _ = try await session.open(data: document.encoded())
        let cases: [(Set<String>, PartTarget?)] = [
            (["alias"], nil), (["actual", "alias"], nil),
            (["actual"], .model), (["actual", "repeated"], .model),
        ]
        for (ids, expected) in cases {
            let snapshot = try await session.selectComponents(ids)
            XCTAssertEqual(snapshot.selectedComponentPartRole, expected, "\(ids)")
            XCTAssertEqual(snapshot.document.encoded(), document.encoded())
            XCTAssertFalse(snapshot.canUndo)
        }
    }

}
