import Dust3DEditorModel
import Foundation
import XCTest

final class SurfaceRepairPreviewStateTests: XCTestCase {
    func testRepairKeepsOriginalFailureUntilCurrentSuccessAndIgnoresOldReceipts() {
        var state = MeshPreviewState<Int>()
        let first = UUID()
        state.begin(requestID: first)
        state.fail("original", requestID: first)
        let repair = UUID()
        state.begin(requestID: repair, preservingError: true)
        XCTAssertEqual(state.errorMessage, "original")
        state.succeed(1, requestID: first)
        XCTAssertEqual(state.errorMessage, "original")
        XCTAssertNil(state.value)
        state.succeed(2, requestID: repair)
        XCTAssertEqual(state.value, 2)
        XCTAssertNil(state.errorMessage)
        let failed = UUID()
        state.begin(requestID: failed)
        state.fail("second", requestID: failed)
        let empty = UUID()
        state.begin(requestID: empty, preservingError: true)
        XCTAssertEqual(state.errorMessage, "second")
        state.succeedEmpty(requestID: empty)
        XCTAssertNil(state.value)
        XCTAssertNil(state.errorMessage)
    }
    func testDefaultBeginStillClearsErrorAndNewFailureSupersedesPreservedCause() {
        var state = MeshPreviewState<Int>()
        let first = UUID()
        state.begin(requestID: first)
        state.fail("original", requestID: first)
        let ordinary = UUID()
        state.begin(requestID: ordinary)
        XCTAssertNil(state.errorMessage)
        state.fail("retry", requestID: ordinary)
        let repair = UUID()
        state.begin(requestID: repair, preservingError: true)
        state.fail("current failure", requestID: repair)
        XCTAssertEqual(state.errorMessage, "current failure")
    }
}
