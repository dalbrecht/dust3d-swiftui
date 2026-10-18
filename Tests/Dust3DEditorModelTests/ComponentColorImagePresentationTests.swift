import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DEditorModel

final class ComponentColorImagePresentationTests: XCTestCase {
    private let identity = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
    private func assets(_ entries: [(String, String)]) throws -> [DocumentColorImageAsset] {
        let payload = Data("<canvas><nodes/><edges/><parts/><components/></canvas>".utf8)
        var header = "<ds3><model name='model.xml' offset='0' size='\(payload.count)'/>"
        for (name, kind) in entries { header += "<\(kind) name='\(name)' offset='\(payload.count)' size='0'/>" }
        header += "</ds3>"
        let prefix = "DUST3D 1.0 xml "
        let archive =
            Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
            + payload
        return try Dust3DDocument(data: archive).colorImageAssets()
    }

    func testAbsentUnsupportedAndMissingReferencesAreExplicit() {
        let absent = ComponentColorImagePresentation(value: .unset, assets: [])
        XCTAssertEqual(absent.source, "No explicit image override.")
        XCTAssertNil(absent.resource)
        let unsupported = ComponentColorImagePresentation(value: .unsupported(""), assets: [])
        XCTAssertTrue(unsupported.source.contains("(empty)"))
        XCTAssertNotNil(unsupported.resource)
        let missing = ComponentColorImagePresentation(value: .reference(identity), assets: [])
        XCTAssertEqual(missing.resource, "The referenced image is missing from this document.")
        XCTAssertNotEqual(absent, missing)
    }

    func testBraceAliasesResolveButCaseDoesNotCollapseAndIssuesRetainCause() throws {
        let name = "images/{\(identity)}.png"
        let rows = try assets([(name, "asset")])
        for raw in [identity, "{\(identity)}"] {
            XCTAssertEqual(
                ComponentColorImagePresentation(value: .reference(raw), assets: rows).resource,
                "Retained resource: \(name)")
        }
        XCTAssertEqual(
            ComponentColorImagePresentation(value: .reference(identity.uppercased()), assets: rows).resource,
            "The referenced image is missing from this document.")
        let wrongKind = try assets([(name, "attachment")])
        XCTAssertEqual(
            ComponentColorImagePresentation(value: .reference(identity), assets: wrongKind).resource,
            ComponentColorImagePresentation.summary(
                TextureImageReferenceError.invalidAssetKind(name).localizedDescription))
        let ambiguous = try assets([(name, "asset"), ("images/\(identity).png", "asset")])
        XCTAssertEqual(
            ComponentColorImagePresentation(value: .reference(identity), assets: ambiguous).resource,
            "Multiple retained assets match image {\(identity)}.")
    }

    func testUntrustedSummaryBoundsCharactersAndCombiningSequenceWork() {
        XCTAssertEqual(ComponentColorImagePresentation.summary(""), "(empty)")
        XCTAssertEqual(ComponentColorImagePresentation.summary("short"), "short")
        XCTAssertEqual(ComponentColorImagePresentation.summary(String(repeating: "a", count: 80)).count, 80)
        XCTAssertEqual(ComponentColorImagePresentation.summary(String(repeating: "a", count: 81)).count, 81)
        XCTAssertTrue(ComponentColorImagePresentation.summary(String(repeating: "a", count: 500)).hasSuffix("…"))
        let combining = "a" + String(repeating: "\u{0301}", count: 10000)
        XCTAssertLessThanOrEqual(ComponentColorImagePresentation.summary(combining).utf8.count, 326)
    }
}
