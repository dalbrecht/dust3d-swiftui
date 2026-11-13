import XCTest

@testable import Dust3DEditor

final class WorkflowReplayPresentationTests: XCTestCase {
    func testPlaybackDistinguishesEmptyReadyInProgressAndComplete() {
        XCTAssertEqual(WorkflowReplayPlaybackPhase(completedSteps: 0, totalSteps: 0), .empty)
        XCTAssertEqual(WorkflowReplayPlaybackPhase(completedSteps: 0, totalSteps: 2), .ready)
        XCTAssertEqual(WorkflowReplayPlaybackPhase(completedSteps: 1, totalSteps: 2), .inProgress)
        XCTAssertEqual(WorkflowReplayPlaybackPhase(completedSteps: 2, totalSteps: 2), .complete)
    }

    func testNextStepAvailableUntilCompletionUnlessReferenceIsPending() {
        XCTAssertTrue(WorkflowReplayPlaybackPhase.ready.canAdvance(waitsForReference: false))
        XCTAssertTrue(WorkflowReplayPlaybackPhase.inProgress.canAdvance(waitsForReference: false))
        XCTAssertFalse(WorkflowReplayPlaybackPhase.ready.canAdvance(waitsForReference: true))
        XCTAssertFalse(WorkflowReplayPlaybackPhase.complete.canAdvance(waitsForReference: false))
        XCTAssertFalse(WorkflowReplayPlaybackPhase.empty.canAdvance(waitsForReference: false))
    }

    func testOnlyPendingReferenceStepBlocksAdvance() {
        XCTAssertTrue(WorkflowReplayReferenceState.loading.blocksAdvance(hasReferenceStep: true, completedSteps: 0))
        XCTAssertFalse(WorkflowReplayReferenceState.loading.blocksAdvance(hasReferenceStep: false, completedSteps: 0))
        XCTAssertFalse(WorkflowReplayReferenceState.loading.blocksAdvance(hasReferenceStep: true, completedSteps: 1))
        XCTAssertFalse(
            WorkflowReplayReferenceState.unavailable("Invalid image")
                .blocksAdvance(hasReferenceStep: true, completedSteps: 0))
    }

    func testStalePreviewErrorYieldsToCurrentFrameProgress() {
        XCTAssertEqual(
            WorkflowReplayMeshStatus(requestedStep: 3, displayedStep: 2, hasMesh: true, failure: "Old frame"),
            .updating)
    }

    func testCurrentPreviewDistinguishesFailureEmptyAndReady() {
        XCTAssertEqual(
            WorkflowReplayMeshStatus(requestedStep: 3, displayedStep: 3, hasMesh: true, failure: "Material error"),
            .failed("Material error"))
        XCTAssertEqual(
            WorkflowReplayMeshStatus(requestedStep: 3, displayedStep: 3, hasMesh: false, failure: nil),
            .empty)
        XCTAssertEqual(
            WorkflowReplayMeshStatus(requestedStep: 3, displayedStep: 3, hasMesh: true, failure: nil),
            .ready)
    }
}
