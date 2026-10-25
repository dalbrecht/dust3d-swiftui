import Foundation
import XCTest

@testable import Dust3DKit

final class HelperCodeSignatureVerifierTests: XCTestCase {
    func testInvalidPolicyFailsBeforeCandidateInspection() {
        let verifier = HelperCodeSignatureVerifier()
        XCTAssertThrowsError(
            try verifier.verify(
                executableURL: URL(fileURLWithPath: "/not-inspected"),
                policy: .developmentAdHoc(codeDirectoryHash: []))
        ) { XCTAssertEqual($0 as? HelperSignatureError, .invalidDevelopmentHash) }
    }

    func testNonFileCandidateRejectsBeforeSecurityAccess() throws {
        let url = try XCTUnwrap(URL(string: "https://example.invalid/helper"))
        XCTAssertThrowsError(
            try HelperCodeSignatureVerifier().verify(
                executableURL: url, policy: .developmentAdHoc(codeDirectoryHash: Array(repeating: 7, count: 20)))
        ) { XCTAssertEqual($0 as? HelperSignatureError, .invalidExecutableURL) }
    }

    func testMissingCandidateRetainsOriginalSecurityCause() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing-helper")
        XCTAssertThrowsError(
            try HelperCodeSignatureVerifier().verify(
                executableURL: url, policy: .developmentAdHoc(codeDirectoryHash: Array(repeating: 7, count: 20)))
        ) { error in
            guard case .securityFailure(let operation, let status, let description) = error as? HelperSignatureError
            else {
                return XCTFail("Expected original Security rejection")
            }
            XCTAssertEqual(operation, .createCode)
            XCTAssertNotEqual(status, 0)
            XCTAssertFalse(description?.isEmpty ?? true)
        }
    }
}
