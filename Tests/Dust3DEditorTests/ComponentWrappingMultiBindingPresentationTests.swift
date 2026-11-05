import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DEditor

final class ComponentWrappingMultiBindingPresentationTests: XCTestCase {
    private func rows(_ a: String, _ b: String) throws -> [DocumentComponent] {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes/><edges/><parts/><components><component id='ancestor' name='Ancestor'><component id='a' wrap='Cloth' \(a)><component id='descendant'/></component><component id='b' wrap='Future' \(b)/></component><component id='body-one' name='Body'/><component id='body-two' name='Body'/><component id='unnamed'/></components></canvas>
                """.utf8)
        ).components()
    }
    private func presentation(_ a: String, _ b: String) throws -> ComponentWrappingMultiBindingPresentation {
        let components = try rows(a, b)
        return try .init(groups: components.filter { ["a", "b"].contains($0.id) }, components: components)
    }
    func testOneCommonCandidateListAndMixedRawSourceValuesNeverImplyAnEdit() throws {
        let value = try presentation("wrapBindTo='body-one'", "wrapBindTo='body-two'")
        XCTAssertEqual(value.candidates.map(\.id), ["ancestor", "body-one", "body-two", "unnamed"])
        XCTAssertEqual(value.currentTitle, "Multiple values")
        XCTAssertEqual(value.accessibilityValue, "Multiple values")
        XCTAssertEqual(value.sources.map(\.value), ["Body: body-one", "Body: body-two"])
        XCTAssertEqual(try presentation("", "wrapBindTo=''").currentTitle, "Own Children")
    }
    func testUniformNamedUnnamedRetainedAndMissingTargetsHaveExactAccessibleValues() throws {
        for (target, title, spoken) in [
            ("body-one", "Body", "Body: body-one"), ("body-two", "Body", "Body: body-two"),
            ("unnamed", "unnamed", "unnamed"), ("a", "Retained source target", "Retained source target: a"),
            ("descendant", "Retained source target", "Retained source target: descendant"),
            ("missing", "Unresolved source reference", "Unresolved source reference: missing"),
        ] {
            let value = try presentation("wrapBindTo='\(target)'", "wrapBindTo='\(target)'")
            XCTAssertEqual(value.currentTitle, title)
            XCTAssertEqual(value.accessibilityValue, spoken)
            XCTAssertEqual(value.sources.map(\.value), [spoken, spoken])
        }
        XCTAssertEqual(try presentation("", "").accessibilityValue, "Own Children")
        XCTAssertEqual(
            try presentation("wrapBindTo=''", "wrapBindTo=''").accessibilityValue, "Own Children")
        let distinct = try presentation("wrapBindTo='caf&#233;'", "wrapBindTo='cafe&#769;'")
        XCTAssertEqual(distinct.currentTitle, "Multiple values")
        XCTAssertFalse(distinct.sources[0].value.utf8.elementsEqual(distinct.sources[1].value.utf8))
    }
    func testEffectiveOwnChildrenCoalescesLosslessRawSpellingsWithoutDocumentWrites() throws {
        let document = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes/><edges/><parts/><components><component id='a'/><component id='b' wrapBindTo=''/></components></canvas>
                """.utf8))
        let bytes = document.encoded()
        let groups = try document.components()
        XCTAssertEqual(groups[0].wrapping.binding, .absent)
        XCTAssertEqual(groups[1].wrapping.binding, .stored(""))
        let value = try ComponentWrappingMultiBindingPresentation(groups: groups, components: groups)
        XCTAssertEqual(value.currentTitle, "Own Children")
        XCTAssertEqual(value.sources.map(\.value), ["Own Children", "Own Children"])
        XCTAssertEqual(document.encoded(), bytes)
    }

    @MainActor func testUnavailableTargetsRetainAnActionableTypedCause() throws {
        do {
            _ = try ComponentWrappingMultiBindingPresentation(groups: [], components: [])
            XCTFail("Unavailable binding plan")
        } catch {
            XCTAssertEqual(error as? DocumentError, .invalidComponentWrapBinding)
            XCTAssertEqual(EditorStore.message(error), "Choose an available body group, or Own Children.")
        }
        XCTAssertEqual(
            EditorStore.message(DocumentError.missingComponent("body")),
            "Component body is not present in this document.")
    }

    func testIndexedIdentitySemanticsDistinguishNFCReferenceFromTheActualNFDTarget() throws {
        let target = "cafe\u{301}"
        let document = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes/><edges/><parts/><components><component id='a' wrapBindTo='caf&#233;'/><component id='b' wrapBindTo='cafe&#769;'/><component id='cafe&#769;' name='Body'/></components></canvas>
                """.utf8))
        let components = try document.components()
        let value = try ComponentWrappingMultiBindingPresentation(
            groups: components.filter { ["a", "b"].contains($0.id) }, components: components)
        XCTAssertEqual(value.currentTitle, "Multiple values")
        XCTAssertEqual(value.sources[0].value, "Unresolved source reference: caf\u{e9}")
        XCTAssertEqual(value.sources[1].value, "Body: \(target)")
        XCTAssertEqual(value.candidates.map(\.id), [target])
        XCTAssertThrowsError(
            try ComponentWrappingMultiBindingPresentation(
                groups: [components[0]], components: components + [components[0]])
        ) {
            XCTAssertEqual($0 as? DocumentError, .invalidComponent)
        }
    }
    func testManyOwnersRetainCandidateAndSourceOrderWithDuplicateDisplayNames() throws {
        let ownerCount = 256
        let targetCount = 32
        let ownerXML = (0..<ownerCount).map { "<component id='owner-\($0)' wrapBindTo='target-\($0 % targetCount)'/>" }
            .joined()
        let targetXML = (0..<targetCount).map { "<component id='target-\($0)' name='Body'/>" }.joined()
        let document = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes/><edges/><parts/><components>\(ownerXML)\(targetXML)</components></canvas>".utf8))
        let components = try document.components()
        let value = try ComponentWrappingMultiBindingPresentation(
            groups: Array(components.prefix(ownerCount)), components: components)
        XCTAssertEqual(value.candidates.map(\.id), (0..<targetCount).map { "target-\($0)" })
        XCTAssertEqual(value.sources.map(\.id), (0..<ownerCount).map { "owner-\($0)" })
        for index in 0..<ownerCount {
            XCTAssertEqual(value.sources[index].value, "Body: target-\(index % targetCount)")
        }
        XCTAssertEqual(value.currentTitle, "Multiple values")
    }

}
