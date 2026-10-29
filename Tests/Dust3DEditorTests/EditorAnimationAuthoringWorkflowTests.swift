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
        return try AnimationAuthoringCatalog(
            clips: [known, long], surfaceMaterials: ["Stone", "Wood"],
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
    private func store(type: String = "Known", catalog: any AnimationCatalogLoading = WorkflowAuthoringCatalog())
        async throws -> EditorStore
    {
        let store = EditorStore(preview: WorkflowAuthoringNoPreview(), animationCatalog: catalog)
        let source = try Dust3DDocument(
            snapshotXML: Data(
                ("<canvas><animations><animation id='a' name='Original' type='" + type
                    + "' speed='1.000' frameCount='legacy' opaque='keep'/></animations></canvas>").utf8))
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
        workflow.beginCreation()
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

    func testTypeAndParameterDraftsPreserveUnsupportedFieldsAndOneStepUndo() async throws {
        let store = try await store(type: "Future")
        defer { store.stop() }
        let workflow = EditorAnimationAuthoringWorkflow(store: store)
        XCTAssertFalse(workflow.canBeginParameters)
        workflow.beginType()
        XCTAssertFalse(workflow.canApply)
        workflow.selectedType = Array("Known".utf8)
        XCTAssertTrue(workflow.canApply)
        workflow.submit()
        try await settle(store)
        let typed = try XCTUnwrap(store.snapshot?.document.encoded())
        XCTAssertEqual(store.animationSnapshot?.list.selectedRow?.source.parameter(named: "opaque"), "keep")
        workflow.beginParameters()
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

    func testStaleAndStoppedDraftsCannotRetargetOrPublishAndInvalidSliderKeepsOriginalCause() async throws {
        let store = try await store()
        defer { store.stop() }
        let workflow = EditorAnimationAuthoringWorkflow(store: store)
        let original = try XCTUnwrap(store.snapshot?.document.encoded())
        workflow.beginCreation()
        await store.load(data: original, fileIdentity: UUID())
        store.selectAnimation("a")
        await store.animationQuery?.value
        XCTAssertFalse(workflow.canApply)
        XCTAssertEqual(workflow.validationIssue as? EditorError, .staleAnimationTarget)
        XCTAssertEqual(workflow.validationMessage, "The document changed. Cancel and start this draft again.")
        workflow.submit()
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
        workflow.cancel()
        workflow.beginParameters()
        workflow.setSlider(name: "speed", index: .nan)
        XCTAssertEqual(workflow.validationIssue as? AnimationCatalogError, .invalidValue)
        XCTAssertEqual(workflow.parameterDraft?.value(for: "speed"), "1.000")
        workflow.setText(name: "durationSeconds", value: "1.125")
        XCTAssertTrue(workflow.canApply)
        workflow.stop()
        workflow.submit()
        workflow.beginCreation()
        XCTAssertFalse(workflow.isActive)
        XCTAssertEqual(store.snapshot?.document.encoded(), original)
    }
    func testActualAuthoringControlsRenderOffscreenWithoutPublishingOrNormalizingSource() async throws {
        for state in [
            "ready", "create", "create-long", "unsupported-type", "parameters", "parameters-unsupported", "stale",
        ] {
            let store = try await store(type: state == "unsupported-type" ? "Future" : "Known")
            defer { store.stop() }
            if state == "parameters-unsupported" {
                let target = try AnimationEditTarget(snapshot: XCTUnwrap(store.animationSnapshot), animationID: "a")
                store.editAnimation(.setParameter(name: "speed", value: "nan"), target: target)
                try await settle(store)
            }
            let workflow = EditorAnimationAuthoringWorkflow(store: store)
            switch state {
            case "create", "create-long", "stale": workflow.beginCreation()
            case "unsupported-type": workflow.beginType()
            case "parameters", "parameters-unsupported": workflow.beginParameters()
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
