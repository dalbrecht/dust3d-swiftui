import Foundation
import XCTest

@testable import Dust3DDocument

final class ComponentColorImageTests: XCTestCase {
    private let imageID = "{iiiiiiii-iiii-iiii-iiii-iiiiiiiiiiii}"
    private var png: Data {
        get throws {
            try XCTUnwrap(
                Data(
                    base64Encoded:
                        "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABAQMAAADO7O3JAAAABlBMVEX/AAAAAP9sof2OAAAAAnRSTlOAAToXZeUAAAAKSURBVHicY3AAAABCAEEpN/TvAAAAAElFTkSuQmCC"
                ))
        }
    }

    private func document(image: String? = "future", assets: [(String, String, Data)] = [], modelOverride: Data? = nil)
        throws -> Dust3DDocument
    {
        let reference = image.map { "colorImageId='\($0)'" } ?? ""
        let model =
            modelOverride
            ?? Data(
                "<canvas xmlns:q='urn:retained'><nodes/><edges/><parts><part id='p'/></parts><components><component id='c' linkDataType='partId' linkData='p' color='#80445566' future='q:Opaque' \(reference)><q:payload/></component><component id='other'/></components></canvas>"
                    .utf8)
        var payload = model
        var header = "<ds3 xmlns:q='urn:header'><model name='model.xml' offset='0' size='\(model.count)'/>"
        for (name, kind, data) in assets + [("opaque.bin", "asset", Data([0, 255, 10, 128]))] {
            header += "<\(kind) name='\(name)' offset='\(payload.count)' size='\(data.count)' future='q:Asset'/>"
            payload.append(data)
        }
        header += "</ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + payload)
    }

    func testShouldImportAndAssignInOneExactHistoryStepWithoutChangingOpaqueData() throws {
        let original = try document()
        XCTAssertEqual(try original.components().first?.colorImage, .unsupported("future"))
        var history = DocumentHistory(document: original)
        try history.apply(.importComponentColorImage(id: "c", imageID: imageID, png: png))
        let changed = history.document
        XCTAssertEqual(try changed.components().first?.colorImage, .reference(imageID))
        XCTAssertEqual(changed.asset(named: "images/\(imageID).png"), try png)
        XCTAssertEqual(changed.asset(named: "opaque.bin"), original.asset(named: "opaque.bin"))
        XCTAssertEqual(try changed.components().first?.color, try original.components().first?.color)
        let xml = try XMLDocument(data: changed.modelXML)
        let component = try XCTUnwrap(try xml.nodes(forXPath: "//component[@id='c']").first as? XMLElement)
        XCTAssertEqual(component.attribute(forName: "future")?.stringValue, "q:Opaque")
        XCTAssertEqual(component.elements(forName: "q:payload").first?.uri, "urn:retained")
        XCTAssertEqual(try Dust3DDocument(data: changed.encoded()).encoded(), changed.encoded())
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertFalse(history.canUndo)
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.document.encoded(), changed.encoded())
    }

    func testShouldAssignSharedExistingImagesClearReferencesAndRetainAssetBytes() throws {
        let name = "images/\(imageID.dropFirst().dropLast()).png"
        let original = try document(image: nil, assets: [(name, "asset", try png)])
        let first = try original.applying(.setComponentColorImage(id: "c", imageID: imageID))
        let shared = try first.applying(.setComponentColorImage(id: "other", imageID: imageID))
        let removed = try shared.applying(.setComponentColorImage(id: "c", imageID: nil))
        XCTAssertEqual(try removed.components().first?.colorImage, .unset)
        XCTAssertEqual(try removed.textureImageReferences().map(\.assetName), [name])
        XCTAssertEqual(removed.asset(named: name), try png)
        XCTAssertEqual(try removed.components().last?.colorImage, .reference(imageID))
        XCTAssertEqual(
            try removed.applying(.setComponentColorImage(id: "c", imageID: nil)).encoded(), removed.encoded())
    }

    func testShouldKeepAliasNoOpsOriginalSpellingAndRedo() throws {
        let raw = String(imageID.dropFirst().dropLast())
        let original = try document(image: raw, assets: [("images/\(imageID).png", "asset", try png)])
        var history = DocumentHistory(document: original)
        try history.apply(.setComponentColorImage(id: "c", imageID: nil))
        XCTAssertTrue(history.undo())
        try history.apply(.setComponentColorImage(id: "c", imageID: imageID))
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertTrue(history.canRedo)
        try history.apply(.importComponentColorImage(id: "c", imageID: imageID, png: png))
        XCTAssertEqual(history.document.encoded(), original.encoded())
        XCTAssertTrue(history.canRedo)
    }

    func testShouldRejectBadImportsAndReferencesWithoutPartialPublication() throws {
        let original = try document()
        for command in [
            DocumentCommand.importComponentColorImage(id: "missing", imageID: imageID, png: try png),
            .importComponentColorImage(id: "c", imageID: "bad", png: try png),
            .importComponentColorImage(id: "c", imageID: imageID, png: Data([1, 2, 3])),
            .setComponentColorImage(id: "c", imageID: imageID),
            .setComponentColorImage(id: "missing", imageID: nil),
            .setComponentColorImage(id: "c", imageID: "bad"),
        ] {
            var history = DocumentHistory(document: original)
            XCTAssertThrowsError(try history.apply(command))
            XCTAssertEqual(history.document.encoded(), original.encoded())
            XCTAssertFalse(history.canUndo)
        }
        for assets in [
            [("images/\(imageID).png", "attachment", try png)],
            [
                ("images/\(imageID).png", "asset", try png),
                ("images/\(imageID.dropFirst().dropLast()).png", "asset", try png),
            ],
            [("images/\(imageID).png", "asset", Data([9]))],
        ] {
            let source = try document(assets: assets)
            XCTAssertThrowsError(try source.applying(.importComponentColorImage(id: "c", imageID: imageID, png: png)))
            XCTAssertEqual(source.asset(named: "opaque.bin"), Data([0, 255, 10, 128]))
        }
    }

    func testShouldRetainNewAssetsInNetZeroReferenceTransactions() throws {
        let original = try document(image: nil)
        var history = DocumentHistory(document: original)
        try history.beginTransaction()
        try history.apply(.importComponentColorImage(id: "c", imageID: imageID, png: png))
        try history.apply(.setComponentColorImage(id: "c", imageID: nil))
        try history.endTransaction()
        XCTAssertEqual(try history.document.components().first?.colorImage, .unset)
        XCTAssertEqual(history.document.asset(named: "images/\(imageID).png"), try png)
        XCTAssertTrue(history.canUndo)
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), original.encoded())
    }
    func testShouldRejectEmptyAssignmentRatherThanRemovingAnExistingReference() throws {
        let source = try document(image: imageID, assets: [("images/\(imageID).png", "asset", try png)])
        XCTAssertThrowsError(try source.applying(.setComponentColorImage(id: "c", imageID: ""))) {
            XCTAssertEqual($0 as? TextureImageReferenceError, .invalidImageIdentity(""))
        }
        XCTAssertEqual(try source.components().first?.colorImage, .reference(imageID))
    }

    func testShouldRejectCanonicalEquivalentAssetNameCollisionsWithoutOverwriting() throws {
        let first = "{a\u{0301}\u{0327}aaa-iiii-iiii-iiii-iiiiiiiiiiii}"
        let second = "{a\u{0327}\u{0301}aaa-iiii-iiii-iiii-iiiiiiiiiiii}"
        let name = "images/\(first).png"
        let source = try document(image: nil, assets: [(name, "asset", try png)])
        XCTAssertThrowsError(try source.applying(.importComponentColorImage(id: "c", imageID: second, png: png))) {
            XCTAssertEqual($0 as? DocumentError, .conflictingAsset("images/\(second).png"))
        }
        XCTAssertNotEqual(ComponentColorImageValue.reference(first), .reference(second))
        XCTAssertNotEqual(ComponentColorImageValue.unsupported(first), .unsupported(second))
        XCTAssertNotEqual(ComponentColorImageValue.unset, .unsupported(""))
        XCTAssertEqual(source.asset(named: name), try png)
    }

    func testShouldKeepEmptySourceNoOpsCaseSensitiveImagesAndZeroIdentity() throws {
        let empty = try document(image: "")
        XCTAssertEqual(try empty.components().first?.colorImage, .unset)
        XCTAssertEqual(try empty.applying(.setComponentColorImage(id: "c", imageID: nil)).encoded(), empty.encoded())
        let lower = try empty.applying(.importComponentColorImage(id: "c", imageID: imageID, png: png))
        let upper = try lower.applying(.importComponentColorImage(id: "other", imageID: imageID.uppercased(), png: png))
        XCTAssertEqual(try upper.textureImageReferences().map(\.imageID), [imageID, imageID.uppercased()])
        XCTAssertEqual(upper.asset(named: "images/\(imageID).png"), try png)
        let zero = "{00000000-0000-0000-0000-000000000000}"
        let imported = try upper.applying(.importComponentColorImage(id: "c", imageID: zero, png: png))
        XCTAssertEqual(try imported.components().first?.colorImage, .reference(zero))
        XCTAssertEqual(imported.asset(named: "images/\(zero).png"), try png)
    }

    func testShouldRejectResourceCapsUnsafeNamesAndImplicitMissingImageRepair() throws {
        let original = try document(image: imageID)
        XCTAssertThrowsError(try original.applying(.importComponentColorImage(id: "c", imageID: imageID, png: png))) {
            XCTAssertEqual($0 as? DocumentError, .conflictingAsset("images/\(imageID).png"))
        }
        let source = try document(image: nil)
        for marker in ["/", ".", "\u{0001}", "\u{FFFE}", "\u{FFFF}"] {
            let bad = imageID.replacingOccurrences(of: "{i", with: "{" + marker)
            XCTAssertThrowsError(try source.applying(.importComponentColorImage(id: "c", imageID: bad, png: png)))
        }
        let excessive = Data(repeating: 0, count: 32 * 1024 * 1024 + 1)
        XCTAssertThrowsError(try source.applying(.importComponentColorImage(id: "c", imageID: imageID, png: excessive)))
        {
            XCTAssertEqual($0 as? PNGContainerError, .encodedLimitExceeded)
        }
        let assets = (0..<9998).map { ("slot-\($0)", "asset", Data()) }
        let full = try document(image: nil, assets: assets)
        XCTAssertThrowsError(try full.applying(.importComponentColorImage(id: "c", imageID: imageID, png: png))) {
            XCTAssertEqual($0 as? DocumentError, .limitExceeded)
        }
        XCTAssertEqual(try source.components().first?.colorImage, .unset)
    }

    func testShouldExposeOriginalReferenceFailureDetails() {
        for (error, expected) in [
            (TextureImageReferenceError.invalidImageIdentity("bad-id"), "bad-id"),
            (.missingAsset("images/missing.png"), "images/missing.png"),
            (.ambiguousAsset(imageID), imageID),
            (.invalidAssetKind("images/wrong.png"), "images/wrong.png"),
        ] { XCTAssertTrue(error.localizedDescription.contains(expected)) }
    }

    func testShouldPublishNothingWhenAssignmentExceedsModelLimitAfterAssetPreparation() throws {
        let baseline = try document(image: nil)
        let oldTag = "<q:payload/>"
        let prefix = "<q:payload>"
        let middle = "</q:payload><q:padding>"
        let suffix = "</q:padding>"
        let overhead = (prefix + middle + suffix).utf8.count - oldTag.utf8.count
        let count = 16 * 1024 * 1024 - baseline.modelXML.count - overhead - 16
        let padding =
            prefix + String(repeating: "x", count: count / 2) + middle
            + String(repeating: "y", count: count - count / 2) + suffix
        let model = String(decoding: baseline.modelXML, as: UTF8.self).replacingOccurrences(of: oldTag, with: padding)
        let source = try document(image: nil, modelOverride: Data(model.utf8))
        var history = DocumentHistory(document: source)
        XCTAssertThrowsError(try history.apply(.importComponentColorImage(id: "c", imageID: imageID, png: png))) {
            XCTAssertEqual($0 as? DocumentError, .limitExceeded)
        }
        XCTAssertEqual(history.document.encoded(), source.encoded())
        XCTAssertNil(history.document.asset(named: "images/\(imageID).png"))
        XCTAssertFalse(history.canUndo)
    }

    func testShouldRestoreOriginalSpellingsAndRedoForNetZeroRetainedImageTransactions() throws {
        for spelling in [String(imageID.dropFirst().dropLast()), imageID, ""] {
            let original = try document(image: spelling, assets: [("images/\(imageID).png", "asset", try png)])
            var history = DocumentHistory(document: original)
            try history.apply(.setComponentName(id: "c", name: "temporary"))
            XCTAssertTrue(history.undo())
            try history.beginTransaction()
            if spelling.isEmpty {
                try history.apply(.setComponentColorImage(id: "c", imageID: imageID))
                try history.apply(.setComponentColorImage(id: "c", imageID: nil))
            } else {
                try history.apply(.setComponentColorImage(id: "c", imageID: nil))
                try history.apply(.setComponentColorImage(id: "c", imageID: imageID))
            }
            try history.endTransaction()
            XCTAssertEqual(history.document.encoded(), original.encoded())
            XCTAssertFalse(history.canUndo)
            XCTAssertTrue(history.canRedo)
        }
    }

}
