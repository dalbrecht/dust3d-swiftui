import AppKit
import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation
import SwiftUI
import XCTest

@testable import Dust3DEditor

private struct WorkflowAuthoringCatalog: AnimationCatalogLoading {
    func load() async throws -> AnimationAuthoringCatalog {
        let speed = try AnimationControlDefinition(
            name: "speed", label: "Speed", minimumSlider: 0, maximumSlider: 200,
            defaultSlider: 100, defaultParameter: 1, divisor: 100, multiplier: 1)
        let amplitude = try AnimationControlDefinition(
            name: "amplitude", label: "Movement amplitude with a long descriptive heading",
            minimumSlider: 0, maximumSlider: 200, defaultSlider: 100, defaultParameter: 0.15, divisor: 667,
            multiplier: 1)
        let known = try AnimationClipDefinition(
            type: "Known", rig: "Biped", generator: "Known", seconds: 4, samples: 90,
            loops: true, isLegacyAlias: false, defaults: [], controls: [speed, amplitude])
        let long = try AnimationClipDefinition(
            type: "KnownLongDirectionalAnimationTypeForLayout", rig: "Biped", generator: "Known",
            seconds: 4, samples: 90, loops: true, isLegacyAlias: false, defaults: [], controls: [])
        let bird = try AnimationClipDefinition(
            type: "BirdFly", rig: "Bird", generator: "BirdFly", seconds: 4, samples: 90,
            loops: true, isLegacyAlias: false, defaults: [], controls: [])
        let legacy = try AnimationClipDefinition(
            type: "LegacyBiped", rig: "Biped", generator: "Known", seconds: 4, samples: 90,
            loops: true, isLegacyAlias: true, defaults: [], controls: [])
        let walk = try AnimationClipDefinition(
            type: "BipedWalk", rig: "Biped", generator: "Known", seconds: 4, samples: 90,
            loops: true, isLegacyAlias: false, defaults: [], controls: [])
        let run = try AnimationClipDefinition(
            type: "bIPEDRun", rig: "Biped", generator: "Known", seconds: 4, samples: 90,
            loops: true, isLegacyAlias: false, defaults: [], controls: [])
        return try AnimationAuthoringCatalog(
            clips: [bird, legacy, known, long, walk, run], surfaceMaterials: ["Stone", "Wood"],
            timing: AnimationTimingDefinition(
                minimumSeconds: 0.01, maximumSeconds: 59.99, decimalPlaces: 2,
                secondsStep: 0.1, minimumFrames: 1, maximumFrames: 4999, framesStep: 5))
    }
}
private struct WorkflowAuthoringNoPreview: EditorPreviewServing {
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult { throw CancellationError() }
    func reset(scopeID: UUID) async throws {}
}

@MainActor
final class EditorAnimationAuthoringWorkflowTests: XCTestCase {
    private func store(
        type: String = "Known", rig: String? = "Biped",
        extraAnimations: String = "",
        catalog: any AnimationCatalogLoading = WorkflowAuthoringCatalog()
    )
        async throws -> EditorStore
    {
        let store = EditorStore(preview: WorkflowAuthoringNoPreview(), animationCatalog: catalog)
        let rigAttribute = rig.map { " rigType='\($0)'" } ?? ""
        let source = try Dust3DDocument(
            snapshotXML: Data(
                ("<canvas\(rigAttribute)><animations><animation id='a' name='Original' type='" + type
                    + "' speed='1.000' frameCount='legacy' opaque='keep'/>\(extraAnimations)</animations></canvas>")
                    .utf8))
        await store.load(data: source.encoded())
        await store.authoringCatalog.load()?.value
        store.selectAnimation("a")
        await store.animationQuery?.value
        return store
    }
    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<300 {
            if !store.isWorking && !store.isLoadingAnimations { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Authoring workflow did not settle")
    }

    func testCreationCommitsDisplayedDefaultsOnceAndCannotBeCancelledAfterAdmission() async throws {
        let store = try await store()
        defer { store.stop() }
        let original = try XCTUnwrap(store.snapshot?.document.encoded())
        let workflow = EditorAnimationAuthoringWorkflow(store: store)
        let previewRevision = store.previewRevision
        workflow.creationAction()()
        XCTAssertTrue(workflow.isActive)
        XCTAssertTrue(workflow.canApply)
        workflow.name = AnimationNameText(" New ")
        workflow.submit()
        XCTAssertTrue(workflow.isSubmitting)
        workflow.cancel()
        workflow.submit()
        XCTAssertTrue(workflow.isActive)
        try await settle(store)
        XCTAssertFalse(workflow.isActive)
        XCTAssertFalse(workflow.isSubmitting)
        let record = try XCTUnwrap(store.animationSnapshot?.list.selectedRow?.source)
        XCTAssertEqual(record.name, " New ")
        XCTAssertEqual(record.parameter(named: "frameCount"), "90")
        XCTAssertEqual(record.parameter(named: "speed"), "1.0")
        XCTAssertEqual(record.parameter(named: "surfaceMaterial"), "Stone")
        XCTAssertEqual(store.animationSnapshot?.list.rows.count, 2)
        XCTAssertEqual(store.previewRevision, previewRevision)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
    }

    func testCreationUsesCanonicalClipsMatchingRawRigAndUndoesExactly() async throws {
        let store = try await store(rig: "bIPED")
        defer { store.stop() }
        let workflow = EditorAnimationAuthoringWorkflow(store: store)
        let original = try XCTUnwrap(store.snapshot?.document.encoded())
        workflow.creationAction()()
        XCTAssertEqual(workflow.selectedClip?.type, "Known")
        for excluded in ["BirdFly", "LegacyBiped"] {
            workflow.selectedType = Array(excluded.utf8)
            XCTAssertFalse(workflow.canApply)
            workflow.submit()
            XCTAssertEqual(store.snapshot?.document.encoded(), original)
        }
        workflow.selectedType = Array("Known".utf8)
        XCTAssertTrue(workflow.canApply)
        workflow.submit()
        try await settle(store)
        XCTAssertEqual(store.animationSnapshot?.list.selectedRow?.source.type, "Known")
        XCTAssertEqual(store.snapshot?.rigSettings.sourceRigType, "bIPED")
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
    }

    func testCreationSuggestsUnusedNameForChosenTypeAndFreshCopy() async throws {
        let store = try await store(
            extraAnimations: "<animation id='walk' name='WALK'/><animation id='second' name='Walk2'/>")
        defer { store.stop() }
        let workflow = EditorAnimationAuthoringWorkflow(store: store)
        let original = try XCTUnwrap(store.snapshot?.document.encoded())
        workflow.creationAction()()
        XCTAssertEqual(workflow.name.value, "known")
        workflow.selectedType = Array("bIPEDRun".utf8)
        XCTAssertEqual(workflow.name.value, "run")
        workflow.selectedType = Array("BipedWalk".utf8)
        XCTAssertEqual(workflow.name.value, "walk3")
        workflow.submit()
        try await settle(store)
        XCTAssertEqual(store.animationSnapshot?.list.selectedRow?.source.name, "walk3")

        workflow.creationAction()()
        workflow.selectedType = Array("BipedWalk".utf8)
        XCTAssertEqual(workflow.name.value, "walk4")
        workflow.cancel()
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
    }

    func testCreationKeepsExactManualNameAcrossTypeChangesAndCancelPublishesNothing() async throws {
        let store = try await store()
        defer { store.stop() }
        let workflow = EditorAnimationAuthoringWorkflow(store: store)
        let original = try XCTUnwrap(store.snapshot?.document.encoded())
        let manual = "  Decomposed e\u{301}  "
        workflow.creationAction()()
        workflow.selectedType = Array("BipedWalk".utf8)
        XCTAssertEqual(workflow.name.value, "walk")
        workflow.name = AnimationNameText(manual)
        workflow.selectedType = Array("bIPEDRun".utf8)
        XCTAssertTrue(workflow.name.value.utf8.elementsEqual(manual.utf8))
        workflow.cancel()
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.canUndo)

        workflow.creationAction()()
        workflow.name = AnimationNameText("Original")
        workflow.selectedType = Array("bIPEDRun".utf8)
        workflow.submit()
        try await settle(store)
        XCTAssertEqual(store.animationSnapshot?.list.selectedRow?.source.name, "Original")
        XCTAssertEqual(store.animationSnapshot?.list.selectedRow?.source.type, "bIPEDRun")
    }

    func testRetainedFormCallbacksCannotChangeOrCancelReopenedCreation() async throws {
        let store = try await store()
        defer { store.stop() }
        let workflow = EditorAnimationAuthoringWorkflow(store: store)
        let original = try XCTUnwrap(store.snapshot?.document.encoded())
        workflow.creationAction()()
        let setName = workflow.draftAction { workflow, value in workflow.name = value }
        let setType = workflow.draftAction { workflow, value in workflow.selectedType = value }
        let cancel = workflow.draftAction { $0.cancel() }
        setType(Array("BipedWalk".utf8))
        setName(AnimationNameText("Current Walk"))
        XCTAssertEqual(workflow.name.value, "Current Walk")

        workflow.cancel()
        workflow.creationAction()()
        let initialName = workflow.name
        let initialType = workflow.selectedType
        setName(AnimationNameText("Retired name"))
        setType(Array("bIPEDRun".utf8))
        XCTAssertEqual(workflow.name, initialName)
        XCTAssertEqual(workflow.selectedType, initialType)
        cancel()
        XCTAssertTrue(workflow.isActive)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.canUndo)
    }

    func testRetainedParameterControlsCannotEditReopenedDraft() async throws {
        let store = try await store()
        defer { store.stop() }
        let workflow = EditorAnimationAuthoringWorkflow(store: store)
        let original = try XCTUnwrap(store.snapshot?.document.encoded())
        workflow.editAction(.parameters)()
        let setFrames = workflow.parameterAction { workflow, value in
            workflow.setText(name: "frameCount", value: value)
        }
        setFrames("120")
        XCTAssertEqual(workflow.parameterValue(for: "frameCount"), "120")

        workflow.cancel()
        workflow.editAction(.parameters)()
        let reopenedFrames = workflow.parameterValue(for: "frameCount")
        setFrames("400")
        XCTAssertEqual(workflow.parameterValue(for: "frameCount"), reopenedFrames)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.canUndo)
    }

    func testNoMatchingRigBlocksCreationButKeepsStoredTypeAndParametersEditable() async throws {
        for rig in [nil, "None", "Unsupported", "Fish"] {
            let store = try await store(type: "LegacyBiped", rig: rig)
            defer { store.stop() }
            let workflow = EditorAnimationAuthoringWorkflow(store: store)
            XCTAssertFalse(workflow.canBeginCreation)
            workflow.creationAction()()
            XCTAssertFalse(workflow.isActive)
            XCTAssertTrue(workflow.canBeginParameters)
            XCTAssertTrue(workflow.canBeginType)
            workflow.editAction(.type)()
            workflow.selectedType = Array("BirdFly".utf8)
            XCTAssertTrue(workflow.canApply)
        }
    }

    func testRigChangeRetiresCreationDraftAndRefreshesEligibleDefault() async throws {
        let store = try await store()
        defer { store.stop() }
        let workflow = EditorAnimationAuthoringWorkflow(store: store)
        let retainedAction = workflow.creationAction()
        workflow.creationAction()()
        store.setRigType(.bird)
        try await settle(store)
        store.refreshAnimations()
        await store.animationQuery?.value
        let changed = try XCTUnwrap(store.snapshot?.document.encoded())
        XCTAssertFalse(workflow.canApply)
        workflow.submit()
        XCTAssertEqual(store.snapshot?.document.encoded(), changed)
        workflow.cancel()
        retainedAction()
        XCTAssertFalse(workflow.isActive)
        workflow.creationAction()()
        XCTAssertEqual(workflow.selectedClip?.type, "BirdFly")
        workflow.selectedType = Array("Known".utf8)
        XCTAssertFalse(workflow.canApply)
    }

    func testTypeAndParameterDraftsPreserveUnsupportedFieldsAndOneStepUndo() async throws {
        let store = try await store(type: "Future")
        defer { store.stop() }
        let workflow = EditorAnimationAuthoringWorkflow(store: store)
        XCTAssertTrue(workflow.canBeginParameters)
        workflow.editAction(.type)()
        XCTAssertFalse(workflow.canApply)
        workflow.selectedType = Array("Known".utf8)
        XCTAssertTrue(workflow.canApply)
        workflow.submit()
        try await settle(store)
        let typed = try XCTUnwrap(store.snapshot?.document.encoded())
        XCTAssertEqual(store.animationSnapshot?.list.selectedRow?.source.parameter(named: "opaque"), "keep")
        workflow.editAction(.parameters)()
        XCTAssertFalse(workflow.canApply)
        workflow.setText(name: "durationSeconds", value: "1.125")
        XCTAssertTrue(workflow.canApply, "An unchanged legacy frame count must not block repairing duration")
        workflow.setText(name: "frameCount", value: "2.5")
        XCTAssertFalse(workflow.canApply)
        workflow.setText(name: "frameCount", value: "2")
        workflow.setSlider(name: "speed", index: 120)
        workflow.submit()
        try await settle(store)
        let record = try XCTUnwrap(store.animationSnapshot?.list.selectedRow?.source)
        XCTAssertEqual(record.parameter(named: "durationSeconds"), "1.125")
        XCTAssertEqual(record.parameter(named: "frameCount"), "2")
        XCTAssertEqual(record.parameter(named: "speed"), "1.2")
        XCTAssertEqual(record.parameter(named: "opaque"), "keep")
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), typed)
    }

    func testParameterApplyKeepsSameRowWithFreshDraftAndSeparateUndoSteps() async throws {
        let store = try await store()
        defer { store.stop() }
        let original = try XCTUnwrap(store.snapshot?.document.encoded())
        let workflow = EditorAnimationAuthoringWorkflow(store: store)
        workflow.editAction(.parameters)()
        let oldSpeed: @MainActor (String) -> Void = workflow.parameterAction { workflow, value in
            workflow.setText(name: "speed", value: value)
        }
        workflow.setText(name: "durationSeconds", value: "1.125")
        XCTAssertEqual(workflow.dismissalTitle, "Cancel")
        workflow.submit()
        try await settle(store)
        let first = try XCTUnwrap(store.snapshot?.document.encoded())
        XCTAssertNotEqual(first, original)
        XCTAssertTrue(workflow.isActive)
        XCTAssertTrue(workflow.isCurrent)
        XCTAssertFalse(workflow.canApply)
        XCTAssertEqual(workflow.parameterValue(for: "durationSeconds"), "1.125")
        XCTAssertEqual(workflow.dismissalTitle, "Done")
        oldSpeed("0.4")
        XCTAssertEqual(workflow.parameterValue(for: "speed"), "1.000")
        XCTAssertFalse(workflow.canApply)

        workflow.setText(name: "speed", value: "0.5")
        XCTAssertTrue(workflow.canApply)
        workflow.submit()
        try await settle(store)
        XCTAssertTrue(workflow.isCurrent)
        XCTAssertFalse(workflow.canApply)
        let row = try XCTUnwrap(store.animationSnapshot?.list.selectedRow?.source)
        XCTAssertEqual(row.id, "a")
        XCTAssertEqual(row.parameter(named: "speed"), "0.5")
        XCTAssertEqual(row.parameter(named: "opaque"), "keep")
        workflow.cancel()
        XCTAssertFalse(workflow.isActive)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), first)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.canUndo)
    }

    func testPendingParameterApplyCannotRebaseToAReplacementWithTheSameRowID() async throws {
        let store = try await store()
        defer { store.stop() }
        let workflow = EditorAnimationAuthoringWorkflow(store: store)
        workflow.editAction(.parameters)()
        workflow.setText(name: "durationSeconds", value: "1.125")
        workflow.submit()
        XCTAssertTrue(workflow.isSubmitting)

        let replacement = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas rigType='Biped'><animations><animation id='a' name='Replacement' type='Known' speed='0.25'/></animations></canvas>"
                    .utf8))
        await store.load(data: replacement.encoded())
        try await settle(store)
        for _ in 0..<300 where workflow.isSubmitting {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(workflow.isSubmitting)
        XCTAssertFalse(workflow.isCurrent)
        XCTAssertFalse(workflow.canApply)
        XCTAssertEqual(store.snapshot?.document.encoded(), replacement.encoded())
        XCTAssertFalse(store.canUndo)
    }

    func testUnknownStoredTypeEditsCommonTimingWithQtDefaultsAndExactUndo() async throws {
        let store = try await store(type: "Future")
        defer { store.stop() }
        let original = try XCTUnwrap(store.snapshot?.document.encoded())
        let preview = store.previewRevision
        let workflow = EditorAnimationAuthoringWorkflow(store: store)
        XCTAssertTrue(workflow.canBeginParameters)
        workflow.editAction(.parameters)()
        let timing = try XCTUnwrap(workflow.unknownParameterDraft)
        XCTAssertEqual(timing.defaultSeconds, 3)
        XCTAssertEqual(timing.defaultFrames, 90)
        XCTAssertNil(workflow.parameterDraft)
        XCTAssertFalse(workflow.canApply)
        workflow.setText(name: "opaque", value: "changed")
        XCTAssertFalse(workflow.canApply)
        workflow.setText(name: "durationSeconds", value: "1.125")
        XCTAssertTrue(workflow.canApply, "Untouched malformed frame count remains preserved")
        workflow.setText(name: "frameCount", value: "2.5")
        XCTAssertFalse(workflow.canApply)
        workflow.useDefault(name: "frameCount")
        XCTAssertTrue(workflow.canApply)
        workflow.submit()
        try await settle(store)

        let encoded = try XCTUnwrap(store.snapshot?.document.encoded())
        let reopened = try Dust3DDocument(data: encoded)
        let record = try XCTUnwrap(try reopened.animations().first)
        XCTAssertEqual(record.type, "Future")
        XCTAssertEqual(record.name, "Original")
        XCTAssertEqual(record.parameter(named: "durationSeconds"), "1.125")
        XCTAssertNil(record.parameter(named: "frameCount"))
        XCTAssertEqual(record.parameter(named: "speed"), "1.000")
        XCTAssertEqual(record.parameter(named: "opaque"), "keep")
        XCTAssertEqual(store.previewRevision, preview)
        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.canUndo)
    }

    func testUnknownStoredTypeCanRepairSurfaceWithoutRewritingOtherParameters() async throws {
        let store = try await store(
            extraAnimations:
                "<animation id='future' name='Future' type='Unknown' surfaceMaterial='Legacy' opaque='keep'/>")
        defer { store.stop() }
        store.selectAnimation("future")
        await store.animationQuery?.value
        let original = try XCTUnwrap(store.snapshot?.document.encoded())
        let workflow = EditorAnimationAuthoringWorkflow(store: store)
        workflow.editAction(.parameters)()
        XCTAssertEqual(workflow.parameterValue(for: "surfaceMaterial"), "Legacy")
        workflow.setText(name: "surfaceMaterial", value: "Unsupported")
        XCTAssertEqual(workflow.validationIssue as? AnimationCatalogError, .invalidValue)
        workflow.setText(name: "surfaceMaterial", value: "Wood")
        XCTAssertTrue(workflow.canApply)
        workflow.submit()
        try await settle(store)

        let changed = try XCTUnwrap(store.snapshot?.document.encoded())
        let reopened = try Dust3DDocument(data: changed)
        let record = try XCTUnwrap(try reopened.animations().first { $0.id == "future" })
        XCTAssertEqual(record.type, "Unknown")
        XCTAssertEqual(record.parameter(named: "surfaceMaterial"), "Wood")
        XCTAssertEqual(record.parameter(named: "opaque"), "keep")
        XCTAssertNil(record.parameter(named: "durationSeconds"))
        XCTAssertNil(record.parameter(named: "frameCount"))

        store.undo()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.canUndo)
    }

    func testRetainedDraftButtonsCannotRetargetAfterSelectionChanges() async throws {
        let store = try await store(extraAnimations: "<animation id='b' name='Second' type='Known'/>")
        defer { store.stop() }
        let workflow = EditorAnimationAuthoringWorkflow(store: store)
        let source = try XCTUnwrap(store.snapshot?.document.encoded())
        let parameters = workflow.editAction(.parameters)
        let type = workflow.editAction(.type)

        store.selectAnimation("b")
        await store.animationQuery?.value
        parameters()
        XCTAssertFalse(workflow.isActive)
        store.selectAnimation("a")
        await store.animationQuery?.value
        type()
        XCTAssertFalse(workflow.isActive, "Returning to a row does not revive its old buttons")

        workflow.editAction(.parameters)()
        XCTAssertTrue(workflow.isActive)
        XCTAssertEqual(workflow.sourceTitle, "Original")
        workflow.cancel()
        workflow.editAction(.type)()
        XCTAssertTrue(workflow.isActive)
        XCTAssertEqual(workflow.sourceTitle, "Original")
        XCTAssertEqual(store.snapshot?.document.encoded(), source)
        XCTAssertFalse(store.canUndo)
    }

    func testUnknownTimingRequiresNamedTypedSourceAndRejectsReplacedArchive() async throws {
        let store = try await store(
            type: "Future",
            extraAnimations: "<animation id='unset' name='Unset'/><animation id='unnamed' type='Future'/>")
        defer { store.stop() }
        let workflow = EditorAnimationAuthoringWorkflow(store: store)
        for id in ["unset", "unnamed"] {
            store.selectAnimation(id)
            await store.animationQuery?.value
            XCTAssertFalse(workflow.canBeginParameters)
        }
        store.selectAnimation("a")
        await store.animationQuery?.value
        workflow.editAction(.parameters)()
        workflow.setText(name: "frameCount", value: "200")
        XCTAssertTrue(workflow.canApply)
        let original = try XCTUnwrap(store.snapshot?.document.encoded())
        await store.load(data: original)
        workflow.submit()
        XCTAssertFalse(workflow.canApply)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        XCTAssertFalse(store.canUndo)
    }

    func testStaleAndStoppedDraftsCannotRetargetOrPublishAndInvalidSliderKeepsOriginalCause() async throws {
        let store = try await store()
        defer { store.stop() }
        let workflow = EditorAnimationAuthoringWorkflow(store: store)
        let original = try XCTUnwrap(store.snapshot?.document.encoded())
        workflow.creationAction()()
        await store.load(data: original, fileIdentity: UUID())
        store.selectAnimation("a")
        await store.animationQuery?.value
        XCTAssertFalse(workflow.canApply)
        XCTAssertEqual(workflow.validationIssue as? EditorError, .staleAnimationTarget)
        XCTAssertEqual(workflow.validationMessage, "The document changed. Cancel and start this draft again.")
        workflow.submit()
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        workflow.cancel()
        workflow.editAction(.parameters)()
        workflow.setSlider(name: "speed", index: .nan)
        XCTAssertEqual(workflow.validationIssue as? AnimationCatalogError, .invalidValue)
        XCTAssertEqual(workflow.parameterDraft?.value(for: "speed"), "1.000")
        workflow.setText(name: "durationSeconds", value: "1.125")
        XCTAssertTrue(workflow.canApply)
        workflow.stop()
        workflow.submit()
        workflow.creationAction()()
        XCTAssertFalse(workflow.isActive)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
    }
    func testActualAuthoringControlsRenderOffscreenWithoutPublishingOrNormalizingSource() async throws {
        for state in [
            "ready", "create", "create-long", "unsupported-type", "parameters", "parameters-unsupported",
            "parameters-unknown", "stale",
        ] {
            let unknown = state == "unsupported-type" || state == "parameters-unknown"
            let store = try await store(type: unknown ? "Future" : "Known")
            defer { store.stop() }
            if state == "parameters-unsupported" {
                let target = try AnimationEditTarget(snapshot: XCTUnwrap(store.animationSnapshot), animationID: "a")
                store.editAnimation(.setParameter(name: "speed", value: "nan"), target: target)
                try await settle(store)
            }
            let workflow = EditorAnimationAuthoringWorkflow(store: store)
            switch state {
            case "create", "create-long", "stale": workflow.creationAction()()
            case "unsupported-type": workflow.editAction(.type)()
            case "parameters", "parameters-unsupported", "parameters-unknown": workflow.editAction(.parameters)()
            default: break
            }
            if state == "create-long" {
                workflow.selectedType = Array("KnownLongDirectionalAnimationTypeForLayout".utf8)
                workflow.name = AnimationNameText("New stored animation with descriptive exact name")
            }
            if state == "stale" {
                let data = try XCTUnwrap(store.snapshot?.document.encoded())
                await store.load(data: data, fileIdentity: UUID())
                store.selectAnimation("a")
                await store.animationQuery?.value
            }
            let before = store.snapshot?.document.encoded()
            var publications = 0
            store.onDocumentChanged = { _ in publications += 1 }
            for scheme in [ColorScheme.light, .dark] {
                let data = try InspectorRenderer.png(
                    AnimationAuthoringControls(store: store, workflow: workflow), width: 250, scheme: scheme)
                let image = try XCTUnwrap(NSBitmapImageRep(data: data))
                XCTAssertGreaterThan(image.pixelsWide, 0)
                XCTAssertGreaterThan(image.pixelsHigh, 0)
                if let path = ProcessInfo.processInfo.environment["DUST3D_UI_QA_OUTPUT_DIR"] {
                    let root = URL(fileURLWithPath: path, isDirectory: true)
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                    try data.write(
                        to: root.appendingPathComponent(
                            "animation-authoring-\(state)-\(scheme == .dark ? "dark" : "light").png"), options: .atomic)
                }
                XCTAssertEqual(store.snapshot?.document.encoded(), before)
                XCTAssertEqual(publications, 0)
            }
            workflow.stop()
        }
    }

}
