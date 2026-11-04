import XCTest

@testable import Dust3DEditor

final class WorkflowReplayPresentationTests: XCTestCase {
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
