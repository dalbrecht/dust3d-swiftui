import Foundation
import XCTest

@testable import Dust3DKit

final class HelperXPCPeerFactoryTests: XCTestCase {
    func testAnonymousObjectsAreConfiguredAndSuspendedForOwnedEndpoint() throws {
        let factory = HelperXPCPeerFactory()
        let policy = HelperSignaturePolicy.developmentAdHoc(codeDirectoryHash: Array(repeating: 7, count: 20))
        let listener = try factory.makeAnonymousListener(policy: policy)
        defer { listener.invalidate() }
        let connection = try factory.makeEndpointConnection(endpoint: listener.endpoint, policy: policy)
        defer { connection.invalidate() }
        XCTAssertNotNil(connection.endpoint)
    }

    func testServiceConnectionRetainsExactNameWithoutActivatingService() throws {
        let connection = try HelperXPCPeerFactory().makeServiceConnection(
            serviceName: "org.dust3d.worker",
            policy: .signedTeam(identifier: "org.dust3d.worker", teamIdentifier: "ABCDE12345"))
        defer { connection.invalidate() }
        XCTAssertEqual(connection.serviceName, "org.dust3d.worker")
    }

    func testInvalidNamesAndPoliciesRejectBeforeCreatingConnections() {
        let factory = HelperXPCPeerFactory()
        let policy = HelperSignaturePolicy.developmentAdHoc(codeDirectoryHash: Array(repeating: 7, count: 20))
        for name in ["", "worker/name", "worker\" or true", "wörker"] {
            XCTAssertThrowsError(try factory.makeServiceConnection(serviceName: name, policy: policy)) {
                XCTAssertEqual($0 as? HelperSignatureError, .invalidIdentifier)
            }
        }
        XCTAssertThrowsError(try factory.makeAnonymousListener(policy: .developmentAdHoc(codeDirectoryHash: []))) {
            XCTAssertEqual($0 as? HelperSignatureError, .invalidDevelopmentHash)
        }
    }
}
