import Foundation
import XCTest

@testable import Dust3DEditor

final class EditorRecoveryDispatchTests: XCTestCase {
    func testBothCommandsProduceRequestsAcceptedOnlyByTheExactReceiver() throws {
        let requestID = UUID()
        for bundle in ["org.dust3d.editor", "org.dust3d.editor.combine-qa"] {
            for (argument, name) in [
                ("--cancel-reference-composition", EditorCompositionRecoveryChannel.notification),
                ("--write-recovery-copies", EditorRecoveryCopyChannel.notification),
            ] {
                let plan = EditorRecoveryDispatchPlan(
                    mode: EditorLaunchMode(arguments: ["editor", argument, "42"]), bundleIdentifier: bundle,
                    requestID: requestID)
                guard case .request(let request) = plan else {
                    return XCTFail("A supported exact target must dispatch")
                }
                XCTAssertEqual(request.notificationName, name)
                XCTAssertEqual(request.bundleIdentifier, bundle)
                XCTAssertEqual(request.userInfo.count, 2)
                let notification = Notification(
                    name: request.notificationName, object: request.bundleIdentifier, userInfo: request.userInfo)
                XCTAssertEqual(
                    EditorRecoveryRequestChannel.requestID(
                        notification, bundleIdentifier: bundle, processIdentifier: 42, notificationName: name),
                    requestID)
                XCTAssertNil(
                    EditorRecoveryRequestChannel.requestID(
                        notification, bundleIdentifier: bundle, processIdentifier: 43, notificationName: name))
                XCTAssertTrue(request.acknowledgement.contains("42"))
                XCTAssertTrue(request.acknowledgement.contains(requestID.uuidString))
                XCTAssertNotEqual(name.rawValue, "org.dust3d.editor.cancel-reference-composition")
            }
        }
    }

    func testApplicationAndRejectedRequestsCannotProduceNotifications() {
        let requestID = UUID()
        XCTAssertTrue(EditorRecoveryDispatchError.invalidCommand.message.contains("PID"))
        XCTAssertTrue(EditorRecoveryDispatchError.unsupportedIdentity.message.contains("bundle"))
        XCTAssertEqual(
            EditorRecoveryDispatchPlan(mode: .application, bundleIdentifier: nil, requestID: requestID), .application)
        XCTAssertEqual(
            EditorRecoveryDispatchPlan(
                mode: .invalidRecoveryCommand, bundleIdentifier: "org.dust3d.editor", requestID: requestID),
            .failure(.invalidCommand))
        for bundle in [nil, "org.dust3d.viewer", ""] {
            XCTAssertEqual(
                EditorRecoveryDispatchPlan(
                    mode: .cancelComposition(processIdentifier: 42), bundleIdentifier: bundle, requestID: requestID),
                .failure(.unsupportedIdentity))
        }
        for processIdentifier: Int32 in [0, -1] {
            XCTAssertEqual(
                EditorRecoveryDispatchPlan(
                    mode: .writeRecoveryCopies(processIdentifier: processIdentifier),
                    bundleIdentifier: "org.dust3d.editor", requestID: requestID), .failure(.invalidCommand))
        }
    }
}
