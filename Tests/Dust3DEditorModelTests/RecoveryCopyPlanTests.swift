import Dust3DEditorModel
import Foundation
import XCTest

final class RecoveryCopyPlanTests: XCTestCase {
    private let first = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa") ?? UUID()
    private let second = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb") ?? UUID()

    func testReplacementAccountsForRetainedCopiesWithoutAppendingRevisions() throws {
        let request = RecoveryCopyRequest(documentID: first, revision: 8, byteCount: 60)
        let inventory = [
            RecoveryCopyInventoryEntry(name: request.filename, byteCount: 70), .init(name: "other.ds3", byteCount: 30),
        ]
        let plan = try RecoveryCopyPlan(requests: [request], inventory: inventory, maximumBytes: 100)
        XCTAssertEqual(plan.requests, [request])
        XCTAssertEqual(plan.retainedByteCount, 90)
        XCTAssertEqual(request.filename, "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.ds3")
        XCTAssertEqual(request.filename, RecoveryCopyRequest(documentID: first, revision: 9, byteCount: 1).filename)
        XCTAssertEqual(try RecoveryCopyPlan(requests: [], inventory: [], maximumBytes: 100).retainedByteCount, 0)
    }

    func testAdmissionRejectsInvalidIdentityRevisionSizesInventoryAndOverflowWithoutAllocatingPayloads() throws {
        let request = RecoveryCopyRequest(documentID: first, revision: 0, byteCount: 50)
        func rejects(
            _ requests: [RecoveryCopyRequest], _ inventory: [RecoveryCopyInventoryEntry] = [], maximum: Int = 100,
            error: RecoveryCopyPlanError
        ) {
            XCTAssertThrowsError(try RecoveryCopyPlan(requests: requests, inventory: inventory, maximumBytes: maximum))
            { XCTAssertEqual($0 as? RecoveryCopyPlanError, error) }
        }
        rejects([request, request], error: .invalidRequest)
        rejects([.init(documentID: first, revision: -1, byteCount: 1)], error: .invalidRequest)
        rejects([.init(documentID: first, revision: 0, byteCount: 0)], error: .invalidRequest)
        rejects([.init(documentID: first, revision: 0, byteCount: -1)], error: .invalidRequest)
        rejects([request], maximum: 0, error: .invalidInventory)
        rejects([request], maximum: Int.max, error: .invalidInventory)
        rejects([.init(documentID: first, revision: 0, byteCount: Int.max)], error: .storageLimitExceeded)
        rejects([request, .init(documentID: second, revision: 0, byteCount: 51)], error: .storageLimitExceeded)
        rejects([request], [.init(name: "other", byteCount: 51)], error: .storageLimitExceeded)
        for name in ["", ".", "..", "../copy", "a/b", "\0", String(repeating: "x", count: 1025)] {
            rejects([], [.init(name: name, byteCount: 1)], error: .invalidInventory)
        }
        rejects([], [.init(name: "x", byteCount: -1)], error: .invalidInventory)
        rejects([], [.init(name: "x", byteCount: 1), .init(name: "x", byteCount: 1)], error: .invalidInventory)
        rejects([], [.init(name: "x", byteCount: Int.max)], error: .storageLimitExceeded)
        rejects(Array(repeating: request, count: 17), error: .tooManyDocuments)
        rejects([], (0..<4097).map { .init(name: String($0), byteCount: 0) }, error: .tooManyFiles)
    }

    func testExactByteLimitAndLargeIntegerAdmissionStayBounded() throws {
        let plan = try RecoveryCopyPlan(
            requests: [.init(documentID: first, revision: Int.max, byteCount: 100)], inventory: [], maximumBytes: 100)
        XCTAssertEqual(plan.retainedByteCount, 100)
        let maximum = RecoveryCopyPlan.maximumRetainedBytes
        XCTAssertEqual(
            try RecoveryCopyPlan(requests: [.init(documentID: first, revision: 0, byteCount: maximum)], inventory: [])
                .retainedByteCount, maximum)
    }

    func testNewCopiesCannotExceedRetainedFileCountButReplacementsCan() throws {
        let request = RecoveryCopyRequest(documentID: first, revision: 0, byteCount: 1)
        let inventory: [RecoveryCopyInventoryEntry] = (0..<4096).map { .init(name: String($0), byteCount: 0) }
        XCTAssertThrowsError(try RecoveryCopyPlan(requests: [request], inventory: inventory)) {
            XCTAssertEqual($0 as? RecoveryCopyPlanError, .tooManyFiles)
        }
        let replacement = Array(inventory.dropLast()) + [.init(name: request.filename, byteCount: 1)]
        XCTAssertEqual(try RecoveryCopyPlan(requests: [request], inventory: replacement).retainedByteCount, 1)
    }

    func testShrinkingCopiesPrecedeGrowthAndEqualSizesUseStableIdentityOrder() throws {
        let left = RecoveryCopyRequest(documentID: first, revision: 1, byteCount: 80)
        let right = RecoveryCopyRequest(documentID: second, revision: 1, byteCount: 20)
        let plan = try RecoveryCopyPlan(
            requests: [left, right],
            inventory: [.init(name: left.filename, byteCount: 60), .init(name: right.filename, byteCount: 40)],
            maximumBytes: 100)
        XCTAssertEqual(plan.requests, [right, left])
        XCTAssertEqual(plan.retainedByteCount, 100)
        let equal = try RecoveryCopyPlan(
            requests: [
                .init(documentID: second, revision: 0, byteCount: 10),
                .init(documentID: first, revision: 0, byteCount: 10),
            ], inventory: [])
        XCTAssertEqual(equal.requests.map(\.documentID), [first, second])
    }
}
