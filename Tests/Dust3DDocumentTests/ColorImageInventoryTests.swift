import Foundation
import XCTest

@testable import Dust3DDocument

final class ColorImageInventoryTests: XCTestCase {
    private func document(_ assets: [(String, String, Data)]) throws -> Dust3DDocument {
        var payload = Data("<canvas><nodes/><edges/><parts/><components/></canvas>".utf8)
        var header = "<ds3><model name='model.xml' offset='0' size='\(payload.count)'/>"
        for (name, kind, data) in assets {
            header += "<\(kind) name='\(name)' offset='\(payload.count)' size='\(data.count)'/>"
            payload.append(data)
        }
        header += "</ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + payload)
    }
    func testShouldInventoryUnreferencedImagesAndRetainExplicitResourceIssuesInSourceOrder() throws {
        let first = "{iiiiiiii-iiii-iiii-iiii-iiiiiiiiiiii}"
        let second = "{jjjjjjjj-jjjj-jjjj-jjjj-jjjjjjjjjjjj}"
        let third = "{kkkkkkkk-kkkk-kkkk-kkkk-kkkkkkkkkkkk}"
        let source = try document([
            ("opaque.bin", "asset", Data([9])),
            ("images/\(first).png", "asset", Data([1, 2])),
            ("images/\(second).png", "asset", Data([3])),
            ("images/\(second.dropFirst().dropLast()).png", "asset", Data([4])),
            ("images/\(third).png", "attachment", Data()),
            ("images/bad.dat", "asset", Data([5])),
        ])
        let before = source.encoded()
        let rows = source.colorImageAssets()
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows.map(\.imageID), [first, second, third, nil])
        XCTAssertTrue(rows[0].canAssign)
        XCTAssertEqual(rows[0].encodedByteCount, 2)
        XCTAssertEqual(rows[1].issue, .ambiguousAsset(second))
        XCTAssertEqual(rows[2].issue, .invalidAssetKind("images/\(third).png"))
        XCTAssertEqual(rows[3].issue, .invalidImageIdentity("bad"))
        XCTAssertTrue(rows.dropFirst().allSatisfy { !$0.canAssign })
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count)
        XCTAssertEqual(source.encoded(), before)
    }
    func testShouldUseByteStableRowIdentitiesForOpaqueUnicodeImageIds() throws {
        let first = "{a\u{0301}\u{0327}aaa-iiii-iiii-iiii-iiiiiiiiiiii}"
        let second = "{a\u{0327}\u{0301}aaa-iiii-iiii-iiii-iiiiiiiiiiii}"
        XCTAssertEqual(first, second)
        let rows = try document([
            ("images/\(first).png", "asset", Data([1])),
            ("images/\(second).dat", "asset", Data([2])),
        ]).colorImageAssets()
        XCTAssertEqual(rows.count, 2)
        XCTAssertNotEqual(rows[0].id, rows[1].id)
        XCTAssertNotEqual(rows[0], rows[1])
    }
}
