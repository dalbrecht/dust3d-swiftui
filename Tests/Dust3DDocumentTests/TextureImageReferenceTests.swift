import Foundation
import XCTest

@testable import Dust3DDocument

final class TextureImageReferenceTests: XCTestCase {
    private let lower = "{iiiiiiii-iiii-iiii-iiii-iiiiiiiiiiii}"

    func testResolvesAliasesAndCaseSensitiveOpaqueIdentitiesWithoutChangingArchive() throws {
        let upper = lower.uppercased()
        let firstName = "images/\(lower).png"
        let secondName = "images/\(upper.dropFirst().dropLast()).png"
        let bytes = archive(
            images: [String(lower.dropFirst().dropLast()), lower, upper],
            assets: [
                (firstName, "asset", Data([1, 2])), (secondName, "asset", Data([3, 4, 5])),
                ("images/unrelated.bin", "asset", Data([255])),
            ])
        let document = try Dust3DDocument(data: bytes)
        let references = try document.textureImageReferences()
        XCTAssertEqual(references.map(\.imageID), [lower, upper])
        XCTAssertEqual(references.map(\.assetName), [firstName, secondName])
        XCTAssertEqual(references.map(\.encodedByteCount), [2, 3])
        XCTAssertEqual(document.encoded(), bytes)
    }

    func testPreservesEmptyReferencesAndNativeZeroIdentitySemantics() throws {
        let zero = "{00000000-0000-0000-0000-000000000000}"
        let bytes = archive(images: ["", zero], assets: [("images/\(zero).png", "asset", Data())])
        let document = try Dust3DDocument(data: bytes)
        let references = try document.textureImageReferences()
        XCTAssertEqual(references.map(\.imageID), [zero])
        XCTAssertEqual(references.first?.encodedByteCount, 0)
        XCTAssertEqual(document.encoded(), bytes)
    }

    func testKeepsCanonicallyEquivalentOpaqueKeysByteDistinct() throws {
        let first = "{a\u{0301}\u{0327}aaa-iiii-iiii-iiii-iiiiiiiiiiii}"
        let second = "{a\u{0327}\u{0301}aaa-iiii-iiii-iiii-iiiiiiiiiiii}"
        XCTAssertEqual(first, second)
        XCTAssertFalse(first.utf8.elementsEqual(second.utf8))
        let firstDocument = try Dust3DDocument(
            data: archive(images: [first], assets: [("images/\(first).png", "asset", Data([1]))]))
        let secondDocument = try Dust3DDocument(
            data: archive(images: [second], assets: [("images/\(second).png", "asset", Data([1]))]))
        let firstReference = try XCTUnwrap(firstDocument.textureImageReferences().first)
        let secondReference = try XCTUnwrap(secondDocument.textureImageReferences().first)
        XCTAssertNotEqual(firstReference, secondReference)
        XCTAssertTrue(firstReference.imageID.utf8.elementsEqual(first.utf8))
        XCTAssertTrue(secondReference.imageID.utf8.elementsEqual(second.utf8))
        let mismatched = try Dust3DDocument(
            data: archive(images: [first], assets: [("images/\(second).png", "asset", Data([1]))]))
        XCTAssertThrowsError(try mismatched.textureImageReferences())
    }

    func testRejectsMissingAmbiguousAndWrongKindAssetsWithoutChangingBytes() throws {
        let name = "images/\(lower).png"
        for assets in [
            [],
            [(name, "attachment", Data([1]))],
            [(name, "asset", Data([1])), ("images/\(lower.dropFirst().dropLast()).png", "asset", Data([1]))],
        ] as [[(String, String, Data)]] {
            let bytes = archive(images: [lower], assets: assets)
            let document = try Dust3DDocument(data: bytes)
            XCTAssertThrowsError(try document.textureImageReferences()) {
                XCTAssertTrue($0 is TextureImageReferenceError)
            }
            XCTAssertEqual(document.encoded(), bytes)
        }
        let document = try Dust3DDocument(data: archive(images: ["bad"], assets: []))
        XCTAssertThrowsError(try document.textureImageReferences()) {
            XCTAssertEqual($0 as? TextureImageReferenceError, .invalidImageIdentity("bad"))
        }
    }

    private func archive(images: [String], assets: [(String, String, Data)]) -> Data {
        let components = images.enumerated().map { index, image in
            "<component id='\(String(format: "{00000000-0000-4000-8000-%012d}", index + 1))' colorImageId='\(image)'/>"
        }.joined()
        let model = Data("<canvas><nodes/><edges/><parts/><components>\(components)</components></canvas>".utf8)
        var payload = model
        var entries = ["<model name='model.xml' offset='0' size='\(model.count)'/>"]
        for (name, kind, bytes) in assets {
            entries.append("<\(kind) name='\(name)' offset='\(payload.count)' size='\(bytes.count)'/>")
            payload.append(bytes)
        }
        let header = Data("<ds3>\(entries.joined())</ds3>".utf8)
        let prefix = Data("DUST3D 1.0 xml \(String(format: "%010d", 26 + header.count))\n".utf8)
        return prefix + header + payload
    }
}
