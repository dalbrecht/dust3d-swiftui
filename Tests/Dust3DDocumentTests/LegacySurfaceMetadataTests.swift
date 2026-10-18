import Foundation
import XCTest

@testable import Dust3DDocument

final class LegacySurfaceMetadataTests: XCTestCase {
    func testLegacySurfaceMetadataMatchesNonemptyReferenceAttributesWithoutChangingSource() throws {
        for (attributes, expected) in [
            ("", false), ("wrapPattern='' wrapWrinkles=''", false),
            ("wrapPattern='future'", true), ("wrapWrinkles='0'", true), ("wrapWrinkles='0.2'", true),
            ("colorImageId='dddddddd-dddd-4ddd-8ddd-dddddddddddd'", false),
        ] {
            let model = Data(
                "<canvas><nodes/><edges/><parts/><components><component id='c' \(attributes)/></components></canvas>"
                    .utf8)
            let header = "<ds3><model name='model.xml' offset='0' size='\(model.count)'/></ds3>"
            let prefix = "DUST3D 1.0 xml "
            let archive =
                Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model
            let document = try Dust3DDocument(data: archive)
            XCTAssertEqual(try XCTUnwrap(document.components().first).hasLegacySurfaceDetails, expected)
            XCTAssertEqual(document.encoded(), archive)
        }
    }
}
