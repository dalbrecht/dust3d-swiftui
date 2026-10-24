import Dust3DDocument
import Foundation
import XCTest

final class DocumentRigSettingsTests: XCTestCase {
    private func document(_ attributes: String = "") throws -> Dust3DDocument {
        let model = Data(
            "<canvas future='keep' \(attributes)><nodes/><edges/><parts/><components/><rig future='retain'/><animations future='retain'/></canvas>"
                .utf8)
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(model.count)'/><asset name='opaque.bin' offset='\(model.count)' size='4'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + Data([0, 255, 10, 128]))
    }

    func testReadsInheritedTypesDefaultsAndUnknownValuesWithoutChangingBytes() throws {
        for text in [
            nil, "", "None", "Biped", "Quadruped", "Bird", "Fish", "Snake", "Insect", "Spider", "future", "biped",
        ] as [String?] {
            let source = try document(text.map { "rigType='\($0)'" } ?? "")
            let settings = try source.rigSettings()
            XCTAssertEqual(settings.sourceRigType, text)
            XCTAssertEqual(
                settings.rigType, (text == nil || text == "") ? .disabled : DocumentRigType(rawValue: text ?? ""))
            XCTAssertFalse(settings.headHasEyelids)
            XCTAssertEqual(try Dust3DDocument(data: source.encoded()).encoded(), source.encoded())
        }
        for text in ["true", "True", "1", "false", "0", "future"] {
            XCTAssertEqual(
                try document("headHasEyelids='\(text)'").rigSettings().headHasEyelids,
                ["true", "True", "1"].contains(text))
        }
    }

    func testRigEditsRetainOpaqueDataAndExactHistory() throws {
        for type in DocumentRigType.allCases {
            let source = try document("rigType='future' headHasEyelids='True'")
            var history = DocumentHistory(document: source)
            try history.apply(.setRigType(type))
            let changed = history.document
            XCTAssertEqual(try changed.rigSettings().rigType, type)
            XCTAssertTrue(try changed.rigSettings().headHasEyelids)
            XCTAssertEqual(changed.asset(named: "opaque.bin"), source.asset(named: "opaque.bin"))
            let xml = try XMLDocument(data: changed.modelXML)
            XCTAssertEqual(xml.rootElement()?.attribute(forName: "future")?.stringValue, "keep")
            XCTAssertEqual(try xml.nodes(forXPath: "/canvas/rig[@future='retain']").count, 1)
            XCTAssertEqual(try xml.nodes(forXPath: "/canvas/animations[@future='retain']").count, 1)
            XCTAssertTrue(history.undo())
            XCTAssertEqual(history.document.encoded(), source.encoded())
            XCTAssertTrue(history.redo())
            XCTAssertEqual(history.document.encoded(), changed.encoded())
            XCTAssertEqual(try Dust3DDocument(data: changed.encoded()).rigSettings(), try changed.rigSettings())
        }
    }

    func testEyelidEditsAndSemanticNoOpsPreserveSourceAndRedo() throws {
        for value in [false, true] {
            let source = try document("rigType='future' headHasEyelids='\(value ? "false" : "True")'")
            var history = DocumentHistory(document: source)
            try history.apply(.setHeadHasEyelids(value))
            let changed = history.document
            XCTAssertEqual(try changed.rigSettings().headHasEyelids, value)
            XCTAssertEqual(try changed.rigSettings().sourceRigType, "future")
            XCTAssertTrue(history.undo())
            XCTAssertEqual(history.document.encoded(), source.encoded())
            try history.apply(.setHeadHasEyelids(!value))
            XCTAssertEqual(history.document.encoded(), source.encoded())
            XCTAssertTrue(history.canRedo)
            XCTAssertTrue(history.redo())
            XCTAssertEqual(history.document.encoded(), changed.encoded())
        }
        for text in [nil, "", "None", "Biped"] as [String?] {
            let source = try document(text.map { "rigType='\($0)'" } ?? "")
            let type = try XCTUnwrap(source.rigSettings().rigType)
            XCTAssertEqual(try source.applying(.setRigType(type)).encoded(), source.encoded())
        }
    }
}
