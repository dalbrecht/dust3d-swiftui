import Dust3DDocument
import XCTest

@testable import Dust3DEditorModel

final class AnimationParameterDraftTests: XCTestCase {
    private func catalog(seconds: Double = 4, surfaces: [String] = ["Stone", "Wood"]) throws
        -> AnimationAuthoringCatalog
    {
        try AnimationAuthoringCatalog(
            clips: [
                AnimationClipDefinition(
                    type: "Known", rig: "Biped", generator: "Known", seconds: seconds, samples: 90,
                    loops: true, isLegacyAlias: false,
                    defaults: [
                        AnimationParameterDefault(name: "speed", value: 1.005),
                        AnimationParameterDefault(name: "presetOnly", value: 3),
                    ],
                    controls: [
                        AnimationControlDefinition(
                            name: "speed", label: "Speed", minimumSlider: 0, maximumSlider: 200,
                            defaultSlider: 100, defaultParameter: 1.005, divisor: 100, multiplier: 1),
                        AnimationControlDefinition(
                            name: "bad", label: "Retained", minimumSlider: 0, maximumSlider: 100,
                            defaultSlider: 50, defaultParameter: 0.5, divisor: 100, multiplier: 1),
                    ])
            ],
            surfaceMaterials: surfaces,
            timing: AnimationTimingDefinition(
                minimumSeconds: 0.01, maximumSeconds: 59.99, decimalPlaces: 2,
                secondsStep: 0.1, minimumFrames: 1, maximumFrames: 4999, framesStep: 5))
    }
    private func record(type: String = "Known") throws -> DocumentAnimation {
        let document = try Dust3DDocument(
            snapshotXML: Data(
                ("<canvas><animations><animation id='a' type='" + type
                    + "' speed='1.000' bad='nan' durationSeconds='unparsed' frameCount='legacy' surfaceMaterial='Future' opaque='keep'/></animations></canvas>")
                    .utf8))
        return try XCTUnwrap(document.animations().first)
    }

    func testUntouchedLegacyParametersRemainExactAndSliderRoundTripRestoresSourceSpelling() throws {
        var draft = try AnimationParameterDraft(record: record(), catalog: catalog())
        XCTAssertTrue(try draft.validatedEdits().isEmpty)
        XCTAssertEqual(draft.value(for: "bad"), "nan")
        XCTAssertEqual(draft.value(for: "opaque"), "keep")
        try draft.setSlider(name: "speed", index: 120)
        XCTAssertEqual(draft.value(for: "speed"), "1.2")
        XCTAssertEqual(try draft.validatedEdits().count, 1)
        try draft.setSlider(name: "speed", index: 100)
        XCTAssertEqual(draft.value(for: "speed"), "1.000")
        XCTAssertTrue(try draft.validatedEdits().isEmpty)
        draft.setText(name: "speed", value: "1.0")
        XCTAssertEqual(try draft.validatedEdits().count, 1, "An explicit spelling edit remains intentional")
        draft.setText(name: "speed", value: "1.000")
        XCTAssertTrue(try draft.validatedEdits().isEmpty)
    }

    func testTimingStepsUseDeclaredIncrementsAndPreserveUneditedRawValues() throws {
        var draft = try AnimationParameterDraft(record: record(), catalog: catalog())
        XCTAssertNil(draft.steppedTimingText(name: "durationSeconds", increasing: true))
        XCTAssertNil(draft.steppedTimingText(name: "frameCount", increasing: false))
        XCTAssertTrue(try draft.validatedEdits().isEmpty)

        draft.useDefault(name: "durationSeconds")
        draft.useDefault(name: "frameCount")
        XCTAssertEqual(draft.steppedTimingText(name: "durationSeconds", increasing: true), "4.1")
        XCTAssertEqual(draft.steppedTimingText(name: "frameCount", increasing: false), "85")

        draft.setText(name: "durationSeconds", value: "59.950")
        draft.setText(name: "frameCount", value: "2")
        XCTAssertEqual(draft.steppedTimingText(name: "durationSeconds", increasing: true), "59.99")
        XCTAssertEqual(draft.steppedTimingText(name: "frameCount", increasing: false), "1")
        XCTAssertEqual(draft.value(for: "durationSeconds"), "59.950")
        draft.setText(name: "durationSeconds", value: "59.990")
        XCTAssertNil(draft.steppedTimingText(name: "durationSeconds", increasing: true))
    }

    func testTimingStepRoundTripRestoresRawSourceAndInheritedDefault() throws {
        let document = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><animations><animation id='a' type='Known' durationSeconds='4.000'/></animations></canvas>"
                    .utf8))
        var draft = try AnimationParameterDraft(record: XCTUnwrap(document.animations().first), catalog: catalog())
        for name in ["durationSeconds", "frameCount"] {
            draft.stepTiming(name: name, increasing: true)
            XCTAssertEqual(try draft.validatedEdits().count, 1)
            draft.stepTiming(name: name, increasing: false)
            XCTAssertTrue(try draft.validatedEdits().isEmpty)
        }
        XCTAssertEqual(draft.value(for: "durationSeconds"), "4.000")
        XCTAssertNil(draft.value(for: "frameCount"))
    }

    func testUnknownTimingStepRoundTripRestoresRawSourceAndInheritedDefault() throws {
        let document = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><animations><animation id='a' name='Legacy' type='Future' frameCount='090'/></animations></canvas>"
                    .utf8))
        var draft = UnknownAnimationParameterDraft(
            record: try XCTUnwrap(document.animations().first), catalog: try catalog())
        for name in ["durationSeconds", "frameCount"] {
            draft.stepTiming(name: name, increasing: true)
            XCTAssertEqual(try draft.validatedEdits().count, 1)
            draft.stepTiming(name: name, increasing: false)
            XCTAssertTrue(try draft.validatedEdits().isEmpty)
        }
        XCTAssertNil(draft.value(for: "durationSeconds"))
        XCTAssertEqual(draft.value(for: "frameCount"), "090")
    }

    func testChangedTimingValidatesIndependentlyOfOtherUnsupportedRetainedFields() throws {
        var draft = try AnimationParameterDraft(record: record(), catalog: catalog())
        draft.setText(name: "durationSeconds", value: "1.125")
        XCTAssertEqual(try draft.validatedEdits().count, 1)
        XCTAssertEqual(draft.value(for: "frameCount"), "legacy")
        draft.setText(name: "frameCount", value: "2.5")
        XCTAssertThrowsError(try draft.validatedEdits()) {
            XCTAssertEqual($0 as? AnimationCatalogError, .unrepresentableValue)
        }
        draft.setText(name: "frameCount", value: "2")
        XCTAssertEqual(try draft.validatedEdits().count, 2)
        draft.setText(name: "durationSeconds", value: "inf")
        XCTAssertThrowsError(try draft.validatedEdits())
        draft.setText(name: "durationSeconds", value: "")
        XCTAssertThrowsError(try draft.validatedEdits())
        draft.useDefault(name: "durationSeconds")
        XCTAssertEqual(try draft.validatedEdits().count, 2)
    }

    func testRepairAndDefaultRemovalDoNotRewriteUnrelatedOrUnsupportedIntent() throws {
        var draft = try AnimationParameterDraft(record: record(), catalog: catalog())
        draft.useDefault(name: "bad")
        guard case .setParameter(let name, let value) = try XCTUnwrap(draft.validatedEdits().first) else {
            return XCTFail("Default means remove the stored override")
        }
        XCTAssertEqual(name, "bad")
        XCTAssertNil(value)
        draft.setText(name: "surfaceMaterial", value: "Wood")
        XCTAssertEqual(try draft.validatedEdits().count, 2)
        XCTAssertEqual(draft.value(for: "opaque"), "keep")
        draft.setText(name: "surfaceMaterial", value: "Unrecognized")
        XCTAssertThrowsError(try draft.validatedEdits())
        draft.setText(name: "surfaceMaterial", value: "Future")
        XCTAssertEqual(try draft.validatedEdits().count, 1, "Restoring unsupported source removes that pending edit")
    }

    func testInvalidExplicitControlsAndUnknownTypesFailWithoutNormalizingSource() throws {
        var draft = try AnimationParameterDraft(record: record(), catalog: catalog())
        XCTAssertThrowsError(try draft.setSlider(name: "speed", index: 201))
        XCTAssertThrowsError(try draft.setSlider(name: "opaque", index: 1))
        XCTAssertTrue(try draft.validatedEdits().isEmpty)
        for value in ["nan", "3", "-1", ""] {
            draft.setText(name: "speed", value: value)
            XCTAssertThrowsError(try draft.validatedEdits())
        }
        draft.setText(name: "speed", value: "1.000")
        draft.setText(name: "opaque", value: "changed")
        XCTAssertThrowsError(try draft.validatedEdits())
        XCTAssertThrowsError(try AnimationParameterDraft(record: record(type: "future"), catalog: catalog()))
    }

    func testCreationUsesDeclaredTimingProjectedWidgetsAndOrderedKnownSurfaceInOnePayload() throws {
        let catalog = try catalog()
        let clip = try XCTUnwrap(catalog.clip(type: "Known"))
        let values = try AnimationParameterDraft.initialParameters(for: clip, in: catalog)
        func value(_ name: String) -> String? { values.first { $0.name == name }?.value }
        XCTAssertEqual(values.count, 6)
        XCTAssertEqual(value("durationSeconds"), "4.0")
        XCTAssertEqual(value("frameCount"), "90")
        XCTAssertEqual(value("speed"), "1.0", "Creation persists the displayed widget position, not nominal 1.005")
        XCTAssertEqual(value("bad"), "0.5")
        XCTAssertEqual(value("presetOnly"), "3.0")
        XCTAssertEqual(value("surfaceMaterial"), "Stone")
        let emptySurfaces = try self.catalog(surfaces: [])
        let withoutSurface = try AnimationParameterDraft.initialParameters(for: clip, in: emptySurfaces)
        XCTAssertFalse(withoutSurface.contains { $0.name == "surfaceMaterial" })
        let invalidTiming = try self.catalog(seconds: 60)
        XCTAssertThrowsError(
            try AnimationParameterDraft.initialParameters(
                for: XCTUnwrap(invalidTiming.clip(type: "Known")), in: invalidTiming))
    }
}
