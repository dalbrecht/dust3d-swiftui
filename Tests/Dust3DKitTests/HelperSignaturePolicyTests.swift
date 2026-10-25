import XCTest

@testable import Dust3DKit

final class HelperSignaturePolicyTests: XCTestCase {
    func testSignedTeamRequiresExactIdentifierAndTeamWithoutAdHocFallback() throws {
        let policy = HelperSignaturePolicy.signedTeam(identifier: "org.dust3d.worker", teamIdentifier: "ABCDE12345")
        let identity = HelperSignatureIdentity(
            identifier: "org.dust3d.worker", teamIdentifier: "ABCDE12345",
            codeDirectoryHash: Array(repeating: 7, count: 20),
            isAdHoc: false)
        XCTAssertNoThrow(try policy.validate(identity))
        XCTAssertThrowsError(try policy.validate(identity.replacing(isAdHoc: true)))
        XCTAssertThrowsError(try policy.validate(identity.replacing(identifier: "org.other.worker")))
        XCTAssertThrowsError(try policy.validate(identity.replacing(teamIdentifier: "ZZZZZ12345")))
        XCTAssertTrue(try policy.requirementExpression().contains("anchor apple generic"))
    }

    func testDevelopmentPinRequiresExactHashAndAdHocSigning() throws {
        let hash = Array(repeating: UInt8(7), count: 20)
        let policy = HelperSignaturePolicy.developmentAdHoc(codeDirectoryHash: hash)
        let identity = HelperSignatureIdentity(
            identifier: "worker", teamIdentifier: nil, codeDirectoryHash: hash, isAdHoc: true)
        XCTAssertNoThrow(try policy.validate(identity))
        XCTAssertThrowsError(try policy.validate(identity.replacing(isAdHoc: false)))
        XCTAssertThrowsError(try policy.validate(identity.replacing(teamIdentifier: "ABCDE12345")))
        XCTAssertThrowsError(try policy.validate(identity.replacing(codeDirectoryHash: Array(repeating: 8, count: 20))))
        XCTAssertEqual(try policy.requirementExpression(), "cdhash H\"" + String(repeating: "07", count: 20) + "\"")
    }

    func testInvalidConfigurationRejectsBeforeRequirementConstruction() {
        for identifier in ["", "worker\" or true", "worker/name", "wörker", String(repeating: "a", count: 256)] {
            XCTAssertThrowsError(
                try HelperSignaturePolicy.signedTeam(identifier: identifier, teamIdentifier: "ABCDE12345")
                    .requirementExpression())
        }
        for team in ["", "abcde12345", "ABC123", "ABCDE1234_", String(repeating: "A", count: 11)] {
            XCTAssertThrowsError(
                try HelperSignaturePolicy.signedTeam(identifier: "org.dust3d.worker", teamIdentifier: team)
                    .requirementExpression())
        }
        for count in [0, 19, 21, 32] {
            XCTAssertThrowsError(
                try HelperSignaturePolicy.developmentAdHoc(codeDirectoryHash: Array(repeating: 0, count: count))
                    .requirementExpression())
        }
    }
}

extension HelperSignatureIdentity {
    fileprivate func replacing(
        identifier: String? = nil, teamIdentifier: String? = nil, codeDirectoryHash: [UInt8]? = nil,
        isAdHoc: Bool? = nil
    ) -> Self {
        Self(
            identifier: identifier ?? self.identifier, teamIdentifier: teamIdentifier ?? self.teamIdentifier,
            codeDirectoryHash: codeDirectoryHash ?? self.codeDirectoryHash, isAdHoc: isAdHoc ?? self.isAdHoc)
    }
}
