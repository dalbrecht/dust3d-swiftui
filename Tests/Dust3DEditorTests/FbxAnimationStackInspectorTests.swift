import Foundation
import XCTest

final class FbxAnimationStackInspectorTests: XCTestCase {
    func testRetainsExactUTF8TitlesAndObjectOrder() throws {
        let titles = [Data("second-id".utf8), Data("  Café 🐟  ".utf8)]
        let stacks = try FbxAnimationStackInspector.inspect(fixture(titles))
        XCTAssertEqual(stacks.map(\.titleUTF8), titles)
        XCTAssertEqual(stacks.map(\.objectID), [100, 101])
    }

    func testStaticObjectsContainNoStacks() throws {
        XCTAssertEqual(try FbxAnimationStackInspector.inspect(fixture([])), [])
    }

    func testRejectsTruncationVersionExtentAndUnknownProperty() {
        let valid = fixture([Data("id".utf8)])
        var version = valid
        version.replaceSubrange(23..<27, with: littleEndian(7500))
        var extent = valid
        extent.replaceSubrange(27..<31, with: littleEndian(valid.count + 1))
        var tag = valid
        tag[27 + 13 + "Objects".utf8.count + 13 + "AnimationStack".utf8.count] = 63
        for invalid in [Data(valid.dropLast(14)), version, extent, tag] {
            XCTAssertThrowsError(try FbxAnimationStackInspector.inspect(invalid))
        }
    }

    func testRejectsDuplicateObjectIDsAndIncorrectClassSuffix() {
        var duplicate = fixture([Data("one".utf8), Data("two".utf8)])
        let firstProperty = 27 + 13 + "Objects".utf8.count + 13 + "AnimationStack".utf8.count
        let secondProperty =
            firstProperty + 13 + "AnimationStack".utf8.count + 9 + 5 + "one\0\u{1}AnimStack".utf8.count + 5
        duplicate.replaceSubrange(secondProperty + 1..<secondProperty + 9, with: littleEndian(100, width: 8))
        XCTAssertThrowsError(try FbxAnimationStackInspector.inspect(duplicate))
        var suffix = fixture([Data("one".utf8)])
        suffix[firstProperty + 9 + 5 + "one\0\u{1}".utf8.count] = 63
        XCTAssertThrowsError(try FbxAnimationStackInspector.inspect(suffix))
    }

    private func littleEndian(_ value: Int, width: Int = 4) -> Data {
        Data((0..<width).map { UInt8(truncatingIfNeeded: UInt64(value) >> (8 * $0)) })
    }

    private func string(_ value: Data) -> Data {
        Data([83]) + littleEndian(value.count) + value
    }

    private func fixture(_ titles: [Data]) -> Data {
        var position = 27 + 13 + "Objects".utf8.count
        var children = Data()
        for (index, title) in titles.enumerated() {
            let properties =
                Data([76]) + littleEndian(100 + index, width: 8)
                + string(title + Data("\0\u{1}AnimStack".utf8)) + string(Data())
            let name = Data("AnimationStack".utf8)
            let end = position + 13 + name.count + properties.count
            children +=
                littleEndian(end) + littleEndian(3) + littleEndian(properties.count)
                + Data([UInt8(name.count)]) + name + properties
            position = end
        }
        let name = Data("Objects".utf8)
        let root =
            littleEndian(position + 13) + littleEndian(0) + littleEndian(0)
            + Data([UInt8(name.count)]) + name + children + Data(repeating: 0, count: 13)
        return Data("Kaydara FBX Binary  \0\u{1a}\0".utf8) + littleEndian(7400)
            + root + Data(repeating: 0, count: 13)
    }
}
