import XCTest

@testable import Dust3DKit

final class MaterialPreviewWarningTests: XCTestCase {
    func testConfirmedSourceBakeRemovesOnlySupportedSurfaceWarnings() {
        let combined = "Untextured preview: image textures and procedural surface details are not yet displayed."
        let imported = "Imported geometry preview: GLB materials, textures and transparency are not yet applied."
        for details: Bool? in [true, false, nil] {
            XCTAssertNil(
                MaterialPreviewWarning.message(
                    combined + " " + imported, hasBakedMaterials: false, hasSourceBakedMaterials: true,
                    hasLegacySurfaceDetails: details))
        }
        XCTAssertEqual(
            MaterialPreviewWarning.message(
                "Original unknown warning. " + imported, hasBakedMaterials: false, hasSourceBakedMaterials: true,
                hasLegacySurfaceDetails: true), "Original unknown warning.")
        XCTAssertEqual(
            MaterialPreviewWarning.message(
                combined, hasBakedMaterials: true, hasSourceBakedMaterials: false,
                hasLegacySurfaceDetails: true), "Procedural surface details are not yet displayed.")
    }

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
    func test_should_remove_only_acknowledged_imported_notice_and_keep_unapplied_procedural_or_unknown_details() {
        let imported = "Imported geometry preview: GLB materials, textures and transparency are not yet applied."
        XCTAssertEqual(
            MaterialPreviewWarning.message(imported, hasBakedMaterials: true, hasLegacySurfaceDetails: false), imported)
        XCTAssertNil(
            MaterialPreviewWarning.message(
                imported, hasBakedMaterials: false, hasImportedMaterials: true, hasLegacySurfaceDetails: false))
        XCTAssertEqual(
            MaterialPreviewWarning.message(
                "Untextured preview: image textures are not yet displayed. " + imported, hasBakedMaterials: false,
                hasImportedMaterials: true, hasLegacySurfaceDetails: false),
            "Component image textures are not yet displayed.")
        XCTAssertEqual(
            MaterialPreviewWarning.message(
                "Untextured preview: image textures and procedural surface details are not yet displayed. " + imported,
                hasBakedMaterials: false, hasImportedMaterials: true, hasLegacySurfaceDetails: true),
            "Component image textures and surface details are not yet displayed.")
        XCTAssertEqual(
            MaterialPreviewWarning.message(
                "Original unknown warning. " + imported, hasBakedMaterials: false, hasImportedMaterials: true,
                hasLegacySurfaceDetails: false), "Original unknown warning.")
    }

}
