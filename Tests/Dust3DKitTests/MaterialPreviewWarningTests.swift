import XCTest

@testable import Dust3DKit

final class MaterialPreviewWarningTests: XCTestCase {
    func testBakedImagesRemoveOnlyRecognizedImageWarnings() {
        let image = "Untextured preview: image textures are not yet displayed."
        let combined = "Untextured preview: image textures and procedural surface details are not yet displayed."
        for warning in [image, combined] {
            XCTAssertEqual(
                MaterialPreviewWarning.message(warning, hasBakedMaterials: false, hasLegacySurfaceDetails: false),
                warning)
            XCTAssertNil(
                MaterialPreviewWarning.message(warning, hasBakedMaterials: true, hasLegacySurfaceDetails: false))
        }
        XCTAssertEqual(
            MaterialPreviewWarning.message(combined, hasBakedMaterials: true, hasLegacySurfaceDetails: true),
            "Procedural surface details are not yet displayed.")
        XCTAssertEqual(
            MaterialPreviewWarning.message(combined, hasBakedMaterials: true, hasLegacySurfaceDetails: nil),
            "Procedural surface details could not be verified.")
        XCTAssertNil(MaterialPreviewWarning.message(image, hasBakedMaterials: true, hasLegacySurfaceDetails: true))
        for baked in [false, true] {
            XCTAssertNil(MaterialPreviewWarning.message("", hasBakedMaterials: baked, hasLegacySurfaceDetails: false))
            XCTAssertEqual(
                MaterialPreviewWarning.message(
                    "Original unknown engine warning", hasBakedMaterials: baked, hasLegacySurfaceDetails: false),
                "Original unknown engine warning")
        }
    }
}
