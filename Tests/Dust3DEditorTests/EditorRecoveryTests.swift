import XCTest

@testable import Dust3DEditor

final class EditorRecoveryTests: XCTestCase {
    func testRecoveryArgumentRequiresExactCommandAndPreservesNormalLaunchArguments() {
        XCTAssertEqual(EditorLaunchMode(arguments: ["editor"]), .application)
        XCTAssertEqual(EditorLaunchMode(arguments: ["editor", "-NSDocumentRevisionsDebugMode", "YES"]), .application)
        XCTAssertEqual(EditorLaunchMode(arguments: ["editor", "--cancel-reference-composition"]), .cancelComposition)
        XCTAssertEqual(
            EditorLaunchMode(arguments: ["editor", "--cancel-reference-composition", "extra"]), .invalidRecoveryCommand)
    }

    @MainActor func testRecoveryCancelsOnlyNewestDraftAndDoesNotFallBackWhenApplying() {
        let recovery = EditorCompositionRecovery()
        let first = UUID()
        let second = UUID()
        let observation = RecoveryObservation()
        XCTAssertFalse(recovery.cancelLatest())
        recovery.register(first) {
            observation.cancelled.append(first)
            return true
        }
        recovery.register(second) {
            guard !observation.isApplying else { return false }
            observation.cancelled.append(second)
            return true
        }
        XCTAssertFalse(recovery.cancelLatest())
        XCTAssertTrue(observation.cancelled.isEmpty)
        observation.isApplying = false
        XCTAssertTrue(recovery.cancelLatest())
        XCTAssertEqual(observation.cancelled, [second])
        recovery.unregister(second)
        XCTAssertTrue(recovery.cancelLatest())
        XCTAssertEqual(observation.cancelled, [second, first])
        recovery.unregister(first)
        XCTAssertFalse(recovery.cancelLatest())
    }

    @MainActor func testRegisteringSamePresentationReplacesItsHandlerAndUnregisterIsIdempotent() {
        let recovery = EditorCompositionRecovery()
        let identifier = UUID()
        var oldHandlerCalled = false
        var replacementCalled = false
        recovery.register(identifier) {
            oldHandlerCalled = true
            return true
        }
        recovery.register(identifier) {
            replacementCalled = true
            return true
        }
        XCTAssertTrue(recovery.cancelLatest())
        XCTAssertFalse(oldHandlerCalled)
        XCTAssertTrue(replacementCalled)
        recovery.unregister(identifier)
        recovery.unregister(identifier)
        XCTAssertFalse(recovery.cancelLatest())
    }
}

@MainActor private final class RecoveryObservation {
    var cancelled: [UUID] = []
    var isApplying = true
}
