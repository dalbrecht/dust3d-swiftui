import XCTest

@testable import Dust3DEditor

final class WorkflowReplayStepAnnouncementTests: XCTestCase {
    func testManualStepAndResetReportCurrentPosition() {
        XCTAssertEqual(
            WorkflowReplayStepAnnouncement.message(step: 1, total: 3, automatic: false, active: true),
            "Step 1 of 3.")
        XCTAssertEqual(
            WorkflowReplayStepAnnouncement.message(step: 0, total: 3, automatic: false, active: true),
            "Ready to replay. Step 0 of 3.")
    }

    func testAutomaticPlaybackAnnouncesOnlyCompletionInActiveWindow() {
        XCTAssertNil(WorkflowReplayStepAnnouncement.message(step: 1, total: 3, automatic: true, active: true))
        XCTAssertNil(WorkflowReplayStepAnnouncement.message(step: 3, total: 3, automatic: true, active: false))
        XCTAssertEqual(
            WorkflowReplayStepAnnouncement.message(step: 3, total: 3, automatic: true, active: true),
            "Replay complete. Step 3 of 3.")
        XCTAssertEqual(
            WorkflowReplayStepAnnouncement.message(step: 3, total: 3, automatic: false, active: true),
            "Replay complete. Step 3 of 3.")
    }

    func testInactiveManualAndInvalidPositionsAreSilent() {
        XCTAssertNil(WorkflowReplayStepAnnouncement.message(step: 1, total: 3, automatic: false, active: false))
        XCTAssertNil(WorkflowReplayStepAnnouncement.message(step: 0, total: 0, automatic: false, active: true))
        XCTAssertNil(WorkflowReplayStepAnnouncement.message(step: 4, total: 3, automatic: false, active: true))
    }
}
