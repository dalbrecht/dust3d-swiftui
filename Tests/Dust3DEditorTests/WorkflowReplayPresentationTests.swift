import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

@testable import Dust3DEditor

final class WorkflowReplayPresentationTests: XCTestCase {
    func testCurrentBoneAssignmentHighlightsOnlyExactVisibleEdgesAndReportsCount() throws {
        let source = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas rigType='Biped'>
                  <nodes>
                    <node id='a' partId='p' x='0' y='0' z='0' radius='.1'/>
                    <node id='b' partId='p' x='1' y='0' z='0' radius='.1'/>
                    <node id='c' partId='p' x='2' y='0' z='0' radius='.1'/>
                    <node id='h' partId='hidden' x='0' y='1' z='0' radius='.1'/>
                    <node id='i' partId='hidden' x='1' y='1' z='0' radius='.1'/>
                  </nodes>
                  <edges>
                    <edge id='head' from='a' to='b' partId='p' boneName='Head'/>
                    <edge id='hip' from='b' to='c' partId='p' boneName='Hips'/>
                    <edge id='hidden-edge' from='h' to='i' partId='hidden' boneName='Head'/>
                  </edges>
                  <parts><part id='p'/><part id='hidden' visible='false'/></parts>
                  <animations><animation id='motion' name='Rest' type='future'/></animations>
                </canvas>
                """.utf8))
        let plan = try WorkflowReplayPlan(document: source)
        let first =
            try XCTUnwrap(
                plan.steps.firstIndex {
                    if case .assignBone(let bone, _) = $0 { return bone.rawValue == "Head" }
                    return false
                }) + 1
        let second = first + 1
        let head = try XCTUnwrap(WorkflowReplayBoneHighlight(plan: plan, completedSteps: first))
        let hips = try XCTUnwrap(WorkflowReplayBoneHighlight(plan: plan, completedSteps: second))
        XCTAssertEqual(head.status, "Assign 2 edges to Head")
        XCTAssertEqual(hips.status, "Assign 1 edge to Hips")
        XCTAssertEqual(head.visibleEdgeIDs(in: plan.frame(after: first)), [Data("head".utf8)])
        XCTAssertEqual(hips.visibleEdgeIDs(in: plan.frame(after: second)), [Data("hip".utf8)])
        XCTAssertNil(WorkflowReplayBoneHighlight(plan: plan, completedSteps: first - 1))
        XCTAssertNil(WorkflowReplayBoneHighlight(plan: plan, completedSteps: second + 1))
        XCTAssertNil(WorkflowReplayBoneHighlight(plan: plan, completedSteps: 0))
        XCTAssertNil(WorkflowReplayBoneHighlight(plan: plan, completedSteps: plan.steps.count + 1))
        XCTAssertEqual(try plan.previewDocument(after: plan.steps.count, source: source).encoded(), source.encoded())
    }

    func testPlaybackDistinguishesEmptyReadyInProgressAndComplete() {
        XCTAssertEqual(WorkflowReplayPlaybackPhase(completedSteps: 0, totalSteps: 0), .empty)
        XCTAssertEqual(WorkflowReplayPlaybackPhase(completedSteps: 0, totalSteps: 2), .ready)
        XCTAssertEqual(WorkflowReplayPlaybackPhase(completedSteps: 1, totalSteps: 2), .inProgress)
        XCTAssertEqual(WorkflowReplayPlaybackPhase(completedSteps: 2, totalSteps: 2), .complete)
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
