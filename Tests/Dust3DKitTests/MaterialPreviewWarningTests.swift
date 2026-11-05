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

    func testConfirmedLegacySurfaceReceiptSuppressesOnlyExactSurfaceNoticeAndRetainsImportedOrUnknownCause() {
        let combined = "Untextured preview: image textures and procedural surface details are not yet displayed."
        let imported = "Imported geometry preview: GLB materials, textures and transparency are not yet applied."
        XCTAssertNil(
            MaterialPreviewWarning.message(
                combined, hasBakedMaterials: true, hasLegacySurfaceDetails: true, hasRenderedSurfaceDetails: true))
        XCTAssertEqual(
            MaterialPreviewWarning.message(
                combined + " " + imported, hasBakedMaterials: true, hasLegacySurfaceDetails: true,
                hasRenderedSurfaceDetails: true), imported)
        for warning in ["Original GPU failure", "Unknown warning. " + combined, combined + " nested unknown", imported]
        {
            XCTAssertEqual(
                MaterialPreviewWarning.message(
                    warning, hasBakedMaterials: true, hasLegacySurfaceDetails: true, hasRenderedSurfaceDetails: true),
                warning)
        }
        XCTAssertEqual(
            MaterialPreviewWarning.message(
                combined, hasBakedMaterials: false, hasLegacySurfaceDetails: true, hasRenderedSurfaceDetails: true),
            combined)
    }

    func testCurrentMaterialWarningAddsNewDetailsWithoutErasingOriginalCausesOrImportedCapabilities() {
        let surface = "Untextured preview: image textures and procedural surface details are not yet displayed."
        let imported = "Imported geometry preview: GLB materials, textures and transparency are not yet applied."
        XCTAssertEqual(
            MaterialPreviewWarning.message(
                "", hasBakedMaterials: false, hasLegacySurfaceDetails: true, materialWarning: surface), surface)
        XCTAssertNil(
            MaterialPreviewWarning.message(
                "", hasBakedMaterials: true, hasLegacySurfaceDetails: true, hasRenderedSurfaceDetails: true,
                materialWarning: surface))
        XCTAssertEqual(
            MaterialPreviewWarning.message(
                "", hasBakedMaterials: true, hasLegacySurfaceDetails: true, hasRenderedSurfaceDetails: true,
                materialWarning: surface + " " + imported), imported)
        XCTAssertEqual(
            MaterialPreviewWarning.message(
                "Original geometry cause", hasBakedMaterials: true, hasLegacySurfaceDetails: true,
                hasRenderedSurfaceDetails: true, materialWarning: surface + " Original material cause"),
            "Original geometry cause\nOriginal material cause")
        XCTAssertEqual(
            MaterialPreviewWarning.message(
                "same", hasBakedMaterials: false, hasLegacySurfaceDetails: false, materialWarning: "same"), "same")
        XCTAssertEqual(
            MaterialPreviewWarning.message(
                "prefix", hasBakedMaterials: false, hasLegacySurfaceDetails: false, materialWarning: "prefix detail"),
            "prefix detail")
        XCTAssertEqual(
            MaterialPreviewWarning.message(
                "prefix detail", hasBakedMaterials: false, hasLegacySurfaceDetails: false, materialWarning: "prefix"),
            "prefix detail")
        XCTAssertEqual(
            MaterialPreviewWarning.message(
                "prefix", hasBakedMaterials: false, hasLegacySurfaceDetails: false, materialWarning: "prefixSuffix"),
            "prefix\nprefixSuffix")
        XCTAssertEqual(
            MaterialPreviewWarning.message(
                "", hasBakedMaterials: true, hasLegacySurfaceDetails: true, hasRenderedSurfaceDetails: true,
                materialWarning: "Unknown nested: " + surface), "Unknown nested: " + surface)
        XCTAssertEqual(
            MaterialPreviewWarning.message(
                "", hasBakedMaterials: true, hasLegacySurfaceDetails: true, hasRenderedSurfaceDetails: true,
                materialWarning: surface + "\u{00A0}original"), surface + "\u{00A0}original")
        XCTAssertNil(
            MaterialPreviewWarning.message(
                "", hasBakedMaterials: true, hasImportedMaterials: true, hasLegacySurfaceDetails: false,
                materialWarning: imported))
        XCTAssertNil(
            MaterialPreviewWarning.message(
                "", hasBakedMaterials: true, hasLegacySurfaceDetails: false,
                materialWarning: "Untextured preview: image textures are not yet displayed."))
    }

    func testOpaquePreparedCausesKeepNestedQuotedAndSuffixCapabilityLiteralsByteExact() {
        let imported = "Imported geometry preview: GLB materials, textures and transparency are not yet applied."
        let surface = "Untextured preview: image textures and procedural surface details are not yet displayed."
        let causes = [
            "Original mip cause: " + imported, "Original quoted cause: '" + imported + "'",
            "Unknown " + surface + " " + imported,
        ]
        for cause in causes {
            for source in [false, true] {
                XCTAssertEqual(
                    MaterialPreviewWarning.message(
                        "", hasBakedMaterials: true, hasImportedMaterials: true, hasSourceBakedMaterials: source,
                        hasLegacySurfaceDetails: true, hasRenderedSurfaceDetails: true, materialWarning: cause), cause)
                XCTAssertEqual(
                    MaterialPreviewWarning.message(
                        "", hasBakedMaterials: true, hasLegacySurfaceDetails: true, hasRenderedSurfaceDetails: true,
                        materialWarning: cause), cause)
            }
            XCTAssertEqual(
                MaterialPreviewWarning.message(
                    "", hasBakedMaterials: true, hasSourceBakedMaterials: true, hasLegacySurfaceDetails: true,
                    materialWarning: surface + " " + cause), cause)
        }
        let composed = "\u{00E9}"
        let decomposed = "e\u{0301}"
        let message = MaterialPreviewWarning.message(
            composed, hasBakedMaterials: false, hasLegacySurfaceDetails: false, materialWarning: decomposed)
        XCTAssertTrue(message?.utf8.elementsEqual((composed + "\n" + decomposed).utf8) == true)
    }

}
