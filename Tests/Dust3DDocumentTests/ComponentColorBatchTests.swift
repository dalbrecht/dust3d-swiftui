import Dust3DDocument
import Foundation
import XCTest

final class ComponentColorBatchTests: XCTestCase {
    private let color = DocumentColor(red: 11, green: 22, blue: 33, alpha: 44)

    private func archive(model: String) throws -> Dust3DDocument {
        let bytes = Data(model.utf8)
        let header =
            "<ds3 future='header'><model name='model.xml' offset='0' size='\(bytes.count)'/><asset name='opaque.bin' offset='\(bytes.count)' size='4' future='asset'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + bytes + Data([0, 255, 10, 128, 77, 88]))
    }

    private func document(extra: String = "", edges: String = "") throws -> Dust3DDocument {
        try archive(
            model:
                "<canvas future='root'><nodes/><edges>\(edges)</edges><parts><part id='p' future='part'/></parts><components><component id='g' color='future' future='group'><component id='c' linkDataType='partId' linkData='p' color='#aB01fF' colorImageId='retained' future='child'/></component>\(extra)</components><future value='opaque'/></canvas>"
        )
    }

    func testBulkColorAndClearMatchIndividualSemanticsAndPreserveOpaqueDataWithOneUndo() throws {
        let source = try document()
        let updates = [
            DocumentComponentColorUpdate(componentID: "g", color: color), .init(componentID: "c", color: nil),
        ]
        var history = DocumentHistory(document: source)
        let initial = history.previewIdentity
        try history.apply(.setComponentColors(updates))
        let changed = history.document
        let expected = try source.applying(.setComponentColor(id: "g", color: color)).applying(
            .setComponentColor(id: "c", color: nil))
        XCTAssertEqual(try changed.components(), try expected.components())
        XCTAssertEqual(changed.asset(named: "opaque.bin"), source.asset(named: "opaque.bin"))
        XCTAssertTrue(changed.encoded().suffix(2).elementsEqual([77, 88]))
        let xml = try XMLDocument(data: changed.modelXML)
        let group = try XCTUnwrap(try xml.nodes(forXPath: "//component[@id='g']").first as? XMLElement)
        let child = try XCTUnwrap(try xml.nodes(forXPath: "//component[@id='c']").first as? XMLElement)
        XCTAssertEqual(group.attribute(forName: "future")?.stringValue, "group")
        XCTAssertEqual(child.attribute(forName: "colorImageId")?.stringValue, "retained")
        XCTAssertEqual(child.attribute(forName: "future")?.stringValue, "child")
        XCTAssertNil(child.attribute(forName: "color"))
        XCTAssertEqual(try xml.nodes(forXPath: "/canvas/future/@value").first?.stringValue, "opaque")
        XCTAssertNotEqual(history.previewIdentity.geometry, initial.geometry)
        XCTAssertNotEqual(history.previewIdentity.materials, initial.materials)
        let acceptedIdentity = history.previewIdentity
        XCTAssertEqual(try Dust3DDocument(data: changed.encoded()).components(), try changed.components())
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), source.encoded())
        XCTAssertEqual(history.previewIdentity, initial)
        XCTAssertFalse(history.canUndo)
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.document.encoded(), changed.encoded())
        XCTAssertEqual(history.previewIdentity, acceptedIdentity)
    }

    func testSemanticAndEmptyNoOpsPreserveExactOriginalSpellingAndRedo() throws {
        let source = try document()
        var history = DocumentHistory(document: source)
        try history.apply(.setComponentColor(id: "c", color: color))
        XCTAssertTrue(history.undo())
        let initial = history.previewIdentity
        try history.apply(.setComponentColors([.init(componentID: "c", color: .init(red: 171, green: 1, blue: 255))]))
        try history.apply(.setComponentColors([]))
        XCTAssertEqual(history.document.encoded(), source.encoded())
        XCTAssertEqual(history.previewIdentity, initial)
        XCTAssertTrue(history.canRedo)
        let opaqueHierarchy = try document(extra: "<component id='g'/>")
        XCTAssertEqual(try opaqueHierarchy.applying(.setComponentColors([])).encoded(), opaqueHierarchy.encoded())
    }

    func testMissingLateOwnerDuplicateUpdatesAndAmbiguousSourceRejectWithoutPartialPublication() throws {
        let source = try document()
        for updates in [
            [DocumentComponentColorUpdate(componentID: "c", color: color), .init(componentID: "missing", color: nil)],
            [.init(componentID: "c", color: color), .init(componentID: "c", color: nil)],
        ] {
            var history = DocumentHistory(document: source)
            try history.apply(.setComponentColor(id: "c", color: color))
            XCTAssertTrue(history.undo())
            let before = history.previewIdentity
            XCTAssertThrowsError(try history.apply(.setComponentColors(updates))) {
                XCTAssertEqual(
                    $0 as? DocumentError,
                    updates.last?.componentID == "missing" ? .missingComponent("missing") : .invalidComponentColor)
            }
            XCTAssertEqual(history.document.encoded(), source.encoded())
            XCTAssertEqual(history.previewIdentity, before)
            XCTAssertTrue(history.canRedo)
        }
        let ambiguous = try document(extra: "<component id='c'/>")
        XCTAssertThrowsError(try ambiguous.applying(.setComponentColors([.init(componentID: "g", color: color)]))) {
            XCTAssertEqual($0 as? DocumentError, .invalidComponent)
        }
        XCTAssertThrowsError(try source.applying(.setComponentColors([.init(componentID: "", color: color)]))) {
            XCTAssertEqual($0 as? DocumentError, .missingComponent(""))
        }
    }

    func testBulkRetainsIndividualGraphValidationInsteadOfEditingAnInvalidGraph() throws {
        let invalid = try document(edges: "<edge id='dangling' from='missing' to='missing'/>")
        for command in [
            DocumentCommand.setComponentColor(id: "g", color: color),
            .setComponentColors([.init(componentID: "g", color: color)]),
        ] {
            XCTAssertThrowsError(try invalid.applying(command)) { XCTAssertEqual($0 as? DocumentError, .invalidNode) }
        }
    }

    func testExistingComponentAndHistoryLimitsRejectBeforePublication() throws {
        let source = try document()
        let oversized = (0...DocumentComponentColorUpdate.maximumBatchCount).map {
            DocumentComponentColorUpdate(componentID: "c\($0)", color: color)
        }
        XCTAssertThrowsError(try source.applying(.setComponentColors(oversized))) {
            XCTAssertEqual($0 as? DocumentError, .limitExceeded)
        }
        var history = DocumentHistory(document: source, maximumUndoBytes: 1)
        XCTAssertThrowsError(try history.apply(.setComponentColors([.init(componentID: "g", color: color)]))) {
            XCTAssertEqual($0 as? DocumentError, .limitExceeded)
        }
        XCTAssertEqual(history.document.encoded(), source.encoded())
        XCTAssertFalse(history.canUndo)
    }

    func testThreeHundredIndependentPartColorsApplyAndClearAsSingleCommands() throws {
        // Ordinary bounded positive data exercises a real many-part transaction; no timing or pressure probe.
        let parts = (0..<300).map { "<part id='p\($0)'/>" }.joined()
        let components = (0..<300).map {
            "<component id='c\($0)' linkDataType='partId' linkData='p\($0)' future='retained'/>"
        }.joined()
        let source = try archive(
            model: "<canvas><nodes/><edges/><parts>\(parts)</parts><components>\(components)</components></canvas>")
        let updates = (0..<300).map {
            DocumentComponentColorUpdate(componentID: "c\($0)", color: .init(red: UInt8($0 % 256), green: 22, blue: 33))
        }
        var history = DocumentHistory(document: source)
        try history.apply(.setComponentColors(updates))
        let changed = try history.document.components()
        XCTAssertEqual(changed.count, 300)
        for index in 0..<300 { XCTAssertEqual(changed[index].color, .value(try XCTUnwrap(updates[index].color))) }
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), source.encoded())
        XCTAssertFalse(history.canUndo)
        XCTAssertTrue(history.redo())
        try history.apply(.setComponentColors(updates.map { .init(componentID: $0.componentID, color: nil) }))
        XCTAssertTrue(try history.document.components().allSatisfy { $0.color == .unset })
        XCTAssertEqual(history.document.asset(named: "opaque.bin"), source.asset(named: "opaque.bin"))
    }

    @MainActor func testPreCancelledBatchLeavesTheImmutableSourceUntouched() async throws {
        let source = try document()
        let bytes = source.encoded()
        let color = color
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try source.applying(.setComponentColors([.init(componentID: "g", color: color)]))
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled batch must not publish a new document")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(source.encoded(), bytes)
    }
}
