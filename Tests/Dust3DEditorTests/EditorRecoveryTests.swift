import XCTest

@testable import Dust3DEditor

final class EditorRecoveryTests: XCTestCase {
    func testUntargetedCompositionCommandIsRejected() {
        XCTAssertEqual(
            EditorLaunchMode(arguments: ["editor", "--cancel-reference-composition"]), .invalidRecoveryCommand)
    }

    @MainActor func testCompositionNotificationDoesNotReuseLegacyBroadcastName() {
        XCTAssertNotEqual(
            EditorCompositionRecoveryChannel.notification.rawValue, "org.dust3d.editor.cancel-reference-composition")
    }

    func testUntargetedCopyCommandIsRejected() {
        XCTAssertEqual(EditorLaunchMode(arguments: ["editor", "--write-recovery-copies"]), .invalidRecoveryCommand)
    }

    func testRecoveryArgumentRequiresExactCommandAndPreservesNormalLaunchArguments() {
        XCTAssertEqual(EditorLaunchMode(arguments: ["editor"]), .application)
        XCTAssertEqual(EditorLaunchMode(arguments: ["editor", "-NSDocumentRevisionsDebugMode", "YES"]), .application)
        XCTAssertEqual(
            EditorLaunchMode(arguments: ["editor", "--cancel-reference-composition", "42"]),
            .cancelComposition(processIdentifier: 42))
        XCTAssertEqual(
            EditorLaunchMode(arguments: ["editor", "--write-recovery-copies", "42"]),
            .writeRecoveryCopies(processIdentifier: 42))
        for value in ["0", "-1", "+42", "042", "2147483648", "1.0", "42 ", "", String(repeating: "1", count: 11)] {
            for command in ["--write-recovery-copies", "--cancel-reference-composition"] {
                XCTAssertEqual(EditorLaunchMode(arguments: ["editor", command, value]), .invalidRecoveryCommand)
            }
        }
        XCTAssertEqual(
            EditorLaunchMode(arguments: ["editor", "--write-recovery-copies", "2147483647"]),
            .writeRecoveryCopies(processIdentifier: Int32.max))
        XCTAssertEqual(
            EditorLaunchMode(arguments: ["editor", "--write-recovery-copies", "extra"]), .invalidRecoveryCommand)
        XCTAssertEqual(
            EditorLaunchMode(arguments: ["editor", "--write-recovery-copies", "--cancel-reference-composition"]),
            .invalidRecoveryCommand)
        XCTAssertEqual(
            EditorLaunchMode(arguments: ["editor", "--cancel-reference-composition", "extra"]), .invalidRecoveryCommand)
    }

    func testCompositionAdmissionRejectsLegacyOtherProcessAndWrongChannel() {
        let id = UUID()
        let info: [String: String] = ["requestID": id.uuidString, "processIdentifier": "42"]
        let name = EditorCompositionRecoveryChannel.notification
        let valid = Notification(name: name, object: "org.dust3d.editor.combine-qa", userInfo: info)
        XCTAssertEqual(
            EditorRecoveryRequestChannel.requestID(
                valid, bundleIdentifier: "org.dust3d.editor.combine-qa",
                processIdentifier: 42, notificationName: name), id)
        XCTAssertNil(
            EditorRecoveryRequestChannel.requestID(
                valid, bundleIdentifier: "org.dust3d.editor.combine-qa",
                processIdentifier: 43, notificationName: name))
        for rejectedName in [
            Notification.Name("org.dust3d.editor.cancel-reference-composition"), EditorRecoveryCopyChannel.notification,
        ] {
            XCTAssertNil(
                EditorRecoveryRequestChannel.requestID(
                    Notification(name: rejectedName, object: "org.dust3d.editor.combine-qa", userInfo: info),
                    bundleIdentifier: "org.dust3d.editor.combine-qa", processIdentifier: 42, notificationName: name))
        }
        XCTAssertNil(
            EditorRecoveryRequestChannel.requestID(
                Notification(name: name, object: "org.dust3d.editor.combine-qa", userInfo: nil),
                bundleIdentifier: "org.dust3d.editor.combine-qa", processIdentifier: 42, notificationName: name))
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
