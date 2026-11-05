import Dust3DDocument
import Foundation
import XCTest

final class ComponentWrappingMultiBindingTests: XCTestCase {
    private func source() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes/><edges/><parts/><components><component id='ancestor' name='Ancestor'><component id='a' wrap='Cloth' wrapBindTo='body' future='keep' wrapPattern='Future'><!--keep--><component id='descendant'/></component><component id='b' wrap='Future' wrapBindTo='missing'/><component id='c' wrapBindTo=''/></component><component id='body' name='Body'/><component id='empty'/><component id='opaque' linkDataType='future' linkData='opaque'/></components></canvas>
                """.utf8))
    }
    func testOneUnionPlanExcludesEveryOwnerAndDescendantButAllowsAncestorsWithoutChangingModes() throws {
        let original = try source()
        for target in ["a", "b", "c", "descendant", "opaque", "missing"] {
            XCTAssertThrowsError(
                try original.applying(.editComponentWrapping(ids: ["a", "b", "c"], edit: .binding(.group(target)))))
        }
        let changed = try original.applying(
            .editComponentWrapping(ids: ["a", "b", "c"], edit: .binding(.group("ancestor"))))
        let selected = try changed.components().filter { ["a", "b", "c"].contains($0.id) }
        XCTAssertEqual(selected.map { $0.wrapping.mode }, [.cloth, nil, ComponentWrapMode.none])
        XCTAssertTrue(selected.allSatisfy { $0.wrapping.binding == .stored("ancestor") })
        let ownerXML = try XCTUnwrap(
            XMLDocument(data: changed.modelXML).nodes(forXPath: "//component[@id='a']").first as? XMLElement)
        XCTAssertEqual(ownerXML.attribute(forName: "future")?.stringValue, "keep")
        XCTAssertEqual(ownerXML.attribute(forName: "wrapPattern")?.stringValue, "Future")
        XCTAssertTrue(String(decoding: changed.modelXML, as: UTF8.self).contains("<!--keep-->"))
        XCTAssertEqual(try Dust3DDocument(data: changed.encoded()).encoded(), changed.encoded())
        // Selecting an ancestor also excludes its entire closure for every selected owner.
        XCTAssertThrowsError(
            try original.applying(.editComponentWrapping(ids: ["ancestor", "b"], edit: .binding(.group("a")))))
    }
    func testBatchBindingHasOneUndoBothPreviewIdentitiesAndSemanticNoopsRetainRedoAndRawEmpty() throws {
        let original = try source()
        var history = DocumentHistory(document: original)
        let before = history.previewIdentity
        try history.apply(.editComponentWrapping(ids: ["a", "b", "c"], edit: .binding(.group("body"))))
        XCTAssertNotEqual(history.previewIdentity.geometry, before.geometry)
        XCTAssertNotEqual(history.previewIdentity.materials, before.materials)
        XCTAssertTrue(
            try history.document.components().filter { ["a", "b", "c"].contains($0.id) }.allSatisfy {
                $0.wrapping.binding == .stored("body")
            })
        history.undo()
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertFalse(history.canUndo)
        try history.apply(.editComponentWrapping(ids: ["a"], edit: .binding(.group("body"))))
        try history.apply(.editComponentWrapping(ids: ["c"], edit: .binding(.ownChildren)))
        XCTAssertTrue(history.canRedo)
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertEqual(try history.document.components().first { $0.id == "c" }?.wrapping.binding, .stored(""))
        history.redo()
        let changed = history.document.encoded()
        try history.apply(.editComponentWrapping(ids: ["c", "b", "a"], edit: .binding(.group("body"))))
        XCTAssertEqual(history.document.encoded(), changed)
        try history.apply(.editComponentWrapping(ids: ["a", "b", "c"], edit: .binding(.ownChildren)))
        XCTAssertTrue(
            try history.document.components().filter { ["a", "b", "c"].contains($0.id) }.allSatisfy {
                $0.wrapping.binding == .absent
            })
    }
    func testInvalidBatchRejectsBeforeAnyFieldMutationAndExactOpaqueSourcesStayUntilReplacement() throws {
        let original = try source()
        for ids in [["a", "missing"], ["a", "a"], ["a", "opaque"], []] {
            XCTAssertThrowsError(try original.applying(.editComponentWrapping(ids: ids, edit: .binding(.ownChildren))))
        }
        XCTAssertEqual(try original.components().first { $0.id == "b" }?.wrapping.binding, .stored("missing"))
        XCTAssertFalse(ComponentWrappingEdit.binding(.ownChildren).isSurfaceOnly)
    }
    func testCanonicalEquivalentReferenceTextIsAnActualExplicitReplacementNotANoop() throws {
        let target = "cafe\u{301}"
        let original = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes/><edges/><parts/><components><component id='a' wrapBindTo='caf&#233;'/><component id='b' wrapBindTo='cafe&#769;'/><component id='cafe&#769;' name='Body'/></components></canvas>
                """.utf8))
        let changed = try original.applying(.editComponentWrapping(ids: ["a", "b"], edit: .binding(.group(target))))
        XCTAssertNotEqual(changed.encoded(), original.encoded())
        let owners = try changed.components().filter { ["a", "b"].contains($0.id) }
        XCTAssertTrue(owners.allSatisfy { $0.wrapping.binding == .stored(target) })
        XCTAssertNotEqual(owners[0].wrapping.binding, .stored("caf\u{e9}"))
        XCTAssertEqual(
            try changed.applying(.editComponentWrapping(ids: ["a", "b"], edit: .binding(.group(target)))).encoded(),
            changed.encoded())
    }

}
