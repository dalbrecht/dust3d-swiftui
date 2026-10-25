import Foundation
import XCTest

@testable import Dust3DEditor

final class ScopedPreviewQueueTests: XCTestCase {
    func testZeroCapacityStartsWithNoWaitingSpace() {
        var queue = ScopedPreviewQueue<Int>(maximumScopes: 0)
        XCTAssertEqual(queue.count, 0)
        XCTAssertEqual(queue.submit(1, scopeID: UUID()), .full)
        XCTAssertNil(queue.takeNext())
    }
    func testDifferentDocumentsRetainTheirWaitingWork() {
        var queue = ScopedPreviewQueue<Int>(maximumScopes: 2)
        let first = UUID()
        let second = UUID()
        XCTAssertEqual(queue.submit(1, scopeID: first), .queued(replaced: nil))
        XCTAssertEqual(queue.submit(2, scopeID: second), .queued(replaced: nil))
        XCTAssertEqual(queue.takeNext(), 1)
        XCTAssertEqual(queue.takeNext(), 2)
        XCTAssertNil(queue.takeNext())
    }

    func testReplacementPreservesOtherDocumentsAndOriginalQueuePosition() {
        var queue = ScopedPreviewQueue<Int>(maximumScopes: 2)
        let first = UUID()
        let second = UUID()
        _ = queue.submit(1, scopeID: first)
        _ = queue.submit(2, scopeID: second)
        XCTAssertEqual(queue.submit(3, scopeID: first), .queued(replaced: 1))
        XCTAssertEqual(queue.takeNext(), 3)
        _ = queue.submit(4, scopeID: first)
        XCTAssertEqual(queue.takeNext(), 2)
        XCTAssertEqual(queue.takeNext(), 4)
    }

    func testCapacityRejectsOnlyNewScopesAndRecoversAfterRemoval() {
        var queue = ScopedPreviewQueue<Int>(maximumScopes: 1)
        let first = UUID()
        let second = UUID()
        _ = queue.submit(1, scopeID: first)
        XCTAssertEqual(queue.submit(2, scopeID: second), .full)
        XCTAssertEqual(queue.submit(3, scopeID: first), .queued(replaced: 1))
        XCTAssertNil(queue.remove(scopeID: second))
        XCTAssertEqual(queue.remove(scopeID: first), 3)
        XCTAssertEqual(queue.submit(4, scopeID: second), .queued(replaced: nil))
        XCTAssertEqual(queue.takeNext(), 4)
    }

    func testCancellationRemovesOnlyTheMatchingWork() {
        var queue = ScopedPreviewQueue<Int>(maximumScopes: 2)
        _ = queue.submit(1, scopeID: UUID())
        _ = queue.submit(2, scopeID: UUID())
        XCTAssertNil(queue.remove { $0 == 3 })
        XCTAssertEqual(queue.remove { $0 == 1 }, 1)
        XCTAssertEqual(queue.takeNext(), 2)
    }
}
