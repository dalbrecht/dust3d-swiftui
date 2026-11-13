import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

@testable import Dust3DEditor

private actor HeldReplayCheckpointPreparation {
    private var pending: CheckedContinuation<EditorFileDocument, Never>?
    private var waiter: CheckedContinuation<Void, Never>?

    func prepare() async -> EditorFileDocument {
        await withCheckedContinuation { continuation in
            pending = continuation
            waiter?.resume()
            waiter = nil
        }
    }

    func waitUntilStarted() async {
        if pending != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func release(_ document: EditorFileDocument) {
        pending?.resume(returning: document)
        pending = nil
    }
}

@MainActor
final class WorkflowReplayCheckpointTests: XCTestCase {
    private final class Presentation {
        var context: WorkflowReplayCheckpoint.Context?
        var opened: [EditorFileDocument] = []
    }

    private func source() throws -> Dust3DDocument {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes><node id='n' partId='p' x='0' y='0' z='0' radius='.1'/></nodes>
                <parts><part id='p'/></parts><animations>
                <animation id='walk' name='Walk' type='Walk' speed='.5'/>
                </animations></canvas>
                """.utf8))
    }

    func testOpensExactPartialAndCompleteBytesAsDistinctDocuments() async throws {
        let original = try source()
        let plan = try WorkflowReplayPlan(document: original)
        let bytes = original.encoded()
        let workflow = WorkflowReplayCheckpoint()
        let presentation = Presentation()
        let sourceID = UUID()
        for step in [1, plan.steps.count, plan.steps.count] {
            let context = WorkflowReplayCheckpoint.Context(sourceID: sourceID, step: step, isPlaying: false)
            presentation.context = context
            let task = try XCTUnwrap(
                workflow.open(
                    plan: plan, source: original, context: context,
                    current: { presentation.context }, deliver: { presentation.opened.append($0) }))
            await task.value
        }
        XCTAssertEqual(presentation.opened.count, 3)
        XCTAssertEqual(Set(presentation.opened.map(\.identity)).count, 3)
        let partial = try XCTUnwrap(presentation.opened.first)
        XCTAssertEqual(partial.data, try plan.previewDocument(after: 1, source: original).encoded())
        XCTAssertTrue(try Dust3DDocument(data: partial.data).animations().isEmpty)
        XCTAssertEqual(presentation.opened[1].data, bytes)
        XCTAssertEqual(presentation.opened[2].data, bytes)
        XCTAssertEqual(original.encoded(), bytes)
        XCTAssertFalse(workflow.isOpening)
        XCTAssertNil(workflow.errorMessage)
    }

    func testRejectsPlayingReadyEmptyAndReplacedContextBeforePreparation() throws {
        let original = try source()
        let plan = try WorkflowReplayPlan(document: original)
        let workflow = WorkflowReplayCheckpoint()
        let sourceID = UUID()
        for context in [
            WorkflowReplayCheckpoint.Context(sourceID: sourceID, step: 0, isPlaying: false),
            .init(sourceID: sourceID, step: 1, isPlaying: true),
            .init(sourceID: sourceID, step: plan.steps.count + 1, isPlaying: false),
        ] {
            XCTAssertNil(
                workflow.open(
                    plan: plan, source: original, context: context, current: { context },
                    deliver: { _ in XCTFail("Invalid step opened") }))
        }
        let valid = WorkflowReplayCheckpoint.Context(sourceID: sourceID, step: 1, isPlaying: false)
        XCTAssertNil(
            workflow.open(
                plan: plan, source: original, context: valid,
                current: { .init(sourceID: UUID(), step: 1, isPlaying: false) },
                deliver: { _ in XCTFail("Replaced source opened") }))
        XCTAssertFalse(workflow.isOpening)
    }

    func testHeldPreparationCannotDeliverAfterPlaybackStepSourceOrCancellation() async throws {
        let original = try source()
        let plan = try WorkflowReplayPlan(document: original)
        let sourceID = UUID()
        let context = WorkflowReplayCheckpoint.Context(sourceID: sourceID, step: 1, isPlaying: false)
        for mode in 0..<4 {
            let gate = HeldReplayCheckpointPreparation()
            let workflow = WorkflowReplayCheckpoint(prepare: { _, _, _ in await gate.prepare() })
            let presentation = Presentation()
            presentation.context = context
            let task = try XCTUnwrap(
                workflow.open(
                    plan: plan, source: original, context: context,
                    current: { presentation.context }, deliver: { presentation.opened.append($0) }))
            await gate.waitUntilStarted()
            XCTAssertTrue(workflow.isOpening)
            XCTAssertNil(
                workflow.open(
                    plan: plan, source: original, context: context,
                    current: { presentation.context }, deliver: { presentation.opened.append($0) }))
            switch mode {
            case 0: presentation.context = .init(sourceID: sourceID, step: 2, isPlaying: false)
            case 1: presentation.context = .init(sourceID: sourceID, step: 1, isPlaying: true)
            case 2: presentation.context = .init(sourceID: UUID(), step: 1, isPlaying: false)
            default:
                workflow.cancel()
                presentation.context = context
            }
            await gate.release(try EditorFileDocument(data: original.encoded()))
            await task.value
            XCTAssertTrue(presentation.opened.isEmpty)
            XCTAssertFalse(workflow.isOpening)
            XCTAssertNil(workflow.errorMessage)
        }
    }

    func testClosingOneReplayWindowDoesNotCancelTheOtherCheckpoint() async throws {
        let source = try source()
        let plan = try WorkflowReplayPlan(document: source)
        let windows = WorkflowReplayWindows()
        let firstID = try XCTUnwrap(windows.open(source, deliver: { _ in }))
        let secondID = try XCTUnwrap(windows.open(source, deliver: { _ in }))
        let firstOwner = UUID()
        let secondOwner = UUID()
        windows.attach(firstID, owner: firstOwner)
        windows.attach(secondID, owner: secondOwner)
        defer { windows.close(secondID, owner: secondOwner) }

        let firstGate = HeldReplayCheckpointPreparation()
        let secondGate = HeldReplayCheckpointPreparation()
        let first = WorkflowReplayCheckpoint(prepare: { _, _, _ in await firstGate.prepare() })
        let second = WorkflowReplayCheckpoint(prepare: { _, _, _ in await secondGate.prepare() })
        let firstContext = WorkflowReplayCheckpoint.Context(sourceID: firstID, step: 1, isPlaying: false)
        let secondContext = WorkflowReplayCheckpoint.Context(
            sourceID: secondID, step: plan.steps.count, isPlaying: false)
        var delivered: [EditorFileDocument] = []
        let firstTask = try XCTUnwrap(
            first.open(
                plan: plan, source: source, context: firstContext,
                current: { windows.request(firstID, owner: firstOwner) == nil ? nil : firstContext },
                deliver: { _ in XCTFail("Closed replay delivered a checkpoint") }))
        let secondTask = try XCTUnwrap(
            second.open(
                plan: plan, source: source, context: secondContext,
                current: { windows.request(secondID, owner: secondOwner) == nil ? nil : secondContext },
                deliver: { delivered.append($0) }))
        await firstGate.waitUntilStarted()
        await secondGate.waitUntilStarted()
        windows.close(firstID, owner: firstOwner)
        let firstBytes = try plan.previewDocument(after: 1, source: source).encoded()
        let secondBytes = try plan.previewDocument(after: plan.steps.count, source: source).encoded()
        XCTAssertNotEqual(firstBytes, secondBytes)
        await firstGate.release(try EditorFileDocument(data: firstBytes))
        await secondGate.release(try EditorFileDocument(data: secondBytes))
        await firstTask.value
        await secondTask.value
        XCTAssertEqual(delivered.map(\.data), [secondBytes])
    }

    func testPreparationErrorIsShownWithoutOpening() async throws {
        let original = try source()
        let plan = try WorkflowReplayPlan(document: original)
        let context = WorkflowReplayCheckpoint.Context(sourceID: UUID(), step: 1, isPlaying: false)
        let workflow = WorkflowReplayCheckpoint(prepare: { _, _, _ in throw DocumentError.invalidXML })
        let task = try XCTUnwrap(
            workflow.open(
                plan: plan, source: original, context: context, current: { context },
                deliver: { _ in XCTFail("Failed preparation opened") }))
        await task.value
        XCTAssertEqual(workflow.errorMessage, EditorStore.message(DocumentError.invalidXML))
        XCTAssertFalse(workflow.isOpening)
    }
}
