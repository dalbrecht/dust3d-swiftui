import XCTest

@testable import Dust3DDocument

final class AnimationAuthoringCatalogTests: XCTestCase {
    private func timing() throws -> AnimationTimingDefinition {
        try AnimationTimingDefinition(
            minimumSeconds: 0.01, maximumSeconds: 59.99, decimalPlaces: 2, secondsStep: 0.1,
            minimumFrames: 1, maximumFrames: 4999, framesStep: 5)
    }
    private func clip(_ type: String = "BipedIdle") throws -> AnimationClipDefinition {
        try AnimationClipDefinition(
            type: type, rig: "Biped", generator: "BipedIdle", seconds: 4, samples: 90,
            loops: true, isLegacyAlias: false,
            defaults: [try AnimationParameterDefault(name: "speed", value: 1.005)],
            controls: [
                try AnimationControlDefinition(
                    name: "speed", label: "Speed", minimumSlider: 0, maximumSlider: 200,
                    defaultSlider: 100, defaultParameter: 1.005, divisor: 100, multiplier: 1)
            ])
    }

    func testOwnedCatalogRetainsOrderExactIdentityAndIndependentNominalDefaults() throws {
        let first = try clip("é")
        let second = try clip("e\u{301}")
        let catalog = try AnimationAuthoringCatalog(
            clips: [first, second], surfaceMaterials: ["Stone", "Wood"], timing: timing())
        XCTAssertEqual(catalog.clips.count, 2)
        XCTAssertEqual(Array(try XCTUnwrap(catalog.clip(type: "é")).type.utf8), Array("é".utf8))
        XCTAssertEqual(Array(try XCTUnwrap(catalog.clip(type: "e\u{301}")).type.utf8), Array("e\u{301}".utf8))
        XCTAssertNil(catalog.clip(type: "future"))
        XCTAssertEqual(catalog.surfaceMaterials, ["Stone", "Wood"])
        XCTAssertEqual(first.defaults.first?.value, 1.005)
        XCTAssertEqual(first.controls.first?.defaultParameter, 1.005)
        XCTAssertEqual(try first.controls.first?.value(at: 100), 1)
        let empty = try AnimationAuthoringCatalog(clips: [], surfaceMaterials: [], timing: timing())
        XCTAssertTrue(empty.clips.isEmpty)
    }

    func testDeclaredTimingValidatesOnlyExplicitMetadataEditsWithoutRoundingOrSampling() throws {
        let timing = try timing()
        XCTAssertNoThrow(try timing.validate(seconds: 0.01, frames: 1))
        XCTAssertNoThrow(try timing.validate(seconds: 59.99, frames: 4999))
        XCTAssertNoThrow(try timing.validate(seconds: 1.125, frames: 2))
        for (seconds, frames) in [(0.0, 30.0), (60.0, 30.0), (1.0, 0.0), (1.0, 5000.0), (.nan, 30.0), (1.0, .infinity)]
        {
            XCTAssertThrowsError(try timing.validate(seconds: seconds, frames: frames)) {
                XCTAssertEqual($0 as? AnimationCatalogError, .invalidValue)
            }
        }
        XCTAssertThrowsError(try timing.validate(seconds: 1.125, frames: 2.5)) {
            XCTAssertEqual($0 as? AnimationCatalogError, .unrepresentableValue)
        }
    }

    func testCatalogRejectsAmbiguousCollectionsAndInvalidIdentities() throws {
        let clip = try clip()
        XCTAssertThrowsError(
            try AnimationAuthoringCatalog(clips: [clip, clip], surfaceMaterials: [], timing: timing())
        ) {
            XCTAssertEqual($0 as? AnimationCatalogError, .invalidDefinition)
        }
        for materials in [["Stone", "Stone"], [""], ["\n"]] {
            XCTAssertThrowsError(
                try AnimationAuthoringCatalog(clips: [], surfaceMaterials: materials, timing: timing())
            ) {
                XCTAssertEqual($0 as? AnimationCatalogError, .invalidDefinition)
            }
        }
        XCTAssertThrowsError(try AnimationParameterDefault(name: "id", value: 1))
        XCTAssertThrowsError(try AnimationParameterDefault(name: "speed", value: .nan))
        XCTAssertThrowsError(try self.clip(""))
        let defaults = [
            try AnimationParameterDefault(name: "speed", value: 1),
            try AnimationParameterDefault(name: "speed", value: 2),
        ]
        XCTAssertThrowsError(
            try AnimationClipDefinition(
                type: "Idle", rig: "Biped", generator: "Idle", seconds: 1, samples: 30, loops: true,
                isLegacyAlias: false, defaults: defaults, controls: []))
        let control = try XCTUnwrap(clip.controls.first)
        XCTAssertThrowsError(
            try AnimationClipDefinition(
                type: "Idle", rig: "Biped", generator: "Idle", seconds: 1, samples: 30, loops: true,
                isLegacyAlias: false, defaults: [], controls: [control, control]))
    }

    func testTimingAndClipAdmissionRejectInvalidDeclarationsWithoutEvaluatingFrames() throws {
        func definition(
            lower: Double = 0.01, upper: Double = 59.99, decimals: Int = 2, step: Double = 0.1,
            first: Int = 1, last: Int = 4999, framesStep: Int = 5
        ) throws -> AnimationTimingDefinition {
            try AnimationTimingDefinition(
                minimumSeconds: lower, maximumSeconds: upper, decimalPlaces: decimals, secondsStep: step,
                minimumFrames: first, maximumFrames: last, framesStep: framesStep)
        }
        let invalid: [() throws -> AnimationTimingDefinition] = [
            { try definition(lower: 0) }, { try definition(lower: 60) }, { try definition(upper: .infinity) },
            { try definition(decimals: 13) }, { try definition(step: 0) }, { try definition(first: 0) },
            { try definition(first: 5000) }, { try definition(last: Int.max) }, { try definition(framesStep: 0) },
            { try definition(framesStep: Int.max) },
        ]
        for build in invalid {
            XCTAssertThrowsError(try build()) { XCTAssertEqual($0 as? AnimationCatalogError, .invalidDefinition) }
        }
        for (seconds, samples) in [(Double.nan, 30), (0.0, 30), (1.0, 0), (1.0, Int.max)] {
            XCTAssertThrowsError(
                try AnimationClipDefinition(
                    type: "Idle", rig: "Biped", generator: "Idle", seconds: seconds, samples: samples,
                    loops: true, isLegacyAlias: false, defaults: [], controls: []))
        }
        XCTAssertFalse(AnimationCatalogError.limitExceeded.localizedDescription.isEmpty)
    }

    func testCollectionCountAdmissionRejectsInvalidScalarCountsWithoutAllocatingPayloads() throws {
        for count in [-1, 2049, Int.max] {
            XCTAssertThrowsError(try AnimationCatalogAdmission.validateCount(count, maximum: 2048)) {
                XCTAssertEqual($0 as? AnimationCatalogError, .limitExceeded)
            }
        }
        XCTAssertNoThrow(try AnimationCatalogAdmission.validateCount(0, maximum: 2048))
        XCTAssertNoThrow(try AnimationCatalogAdmission.validateCount(2048, maximum: 2048))
    }
}
