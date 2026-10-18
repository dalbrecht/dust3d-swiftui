import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DKit

final class MaterialSourceCapabilitiesTests: XCTestCase {
    private func archive(_ attributes: String, children: String = "") -> Data {
        let model = Data(
            "<canvas><nodes/><edges/><parts/><components><component id='c' \(attributes)>\(children)</component></components></canvas>"
                .utf8)
        let header = "<ds3><model name='model.xml' offset='0' size='\(model.count)'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
            + model
    }

    func testReadOnlyCapabilitiesDistinguishImagesFromLegacySurfaceMetadata() {
        for (attributes, expected) in [
            ("", false), ("colorImageId='dddddddd-dddd-4ddd-8ddd-dddddddddddd'", false),
            ("wrapPattern='future'", true), ("wrapWrinkles='0'", true),
        ] {
            let data = archive(attributes)
            let capabilities = MaterialSourceCapabilities.read(data: data)
            XCTAssertEqual(capabilities.hasLegacySurfaceDetails, expected)
            XCTAssertNil(capabilities.issue)
            XCTAssertEqual(data, archive(attributes))
        }
        XCTAssertNil(MaterialSourceCapabilities.unknown.hasLegacySurfaceDetails)
        XCTAssertNil(MaterialSourceCapabilities.unknown.issue)
    }

    func testFailedInterpretationKeepsOriginalTypedCauseInsteadOfClaimingNoLegacyDetails() {
        for data in [Data(), archive("", children: "<future id='opaque'/>")] {
            let capabilities = MaterialSourceCapabilities.read(data: data)
            XCTAssertNil(capabilities.hasLegacySurfaceDetails)
            XCTAssertNotNil(capabilities.issue as? DocumentError)
        }
    }
}
