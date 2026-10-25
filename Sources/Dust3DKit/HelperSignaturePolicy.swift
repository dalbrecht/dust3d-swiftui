/// Independently copied signing facts. Constructing facts does not authenticate a binary.
public struct HelperSignatureIdentity: Equatable, Sendable {
    public let identifier: String
    public let teamIdentifier: String?
    public let codeDirectoryHash: [UInt8]
    public let isAdHoc: Bool

    /// Creates value-only facts for policy evaluation; production facts come from Security verification.
    public init(identifier: String, teamIdentifier: String?, codeDirectoryHash: [UInt8], isAdHoc: Bool) {
        self.identifier = identifier
        self.teamIdentifier = teamIdentifier
        self.codeDirectoryHash = codeDirectoryHash
        self.isAdHoc = isAdHoc
    }
}

/// Operation preserving an original Security OSStatus and optional framework description.
public enum HelperSignatureOperation: String, Sendable {
    case createCode, createRequirement, validateCode, readInformation
}

/// Typed configuration, policy or platform rejection; no automatic alternate trust policy is attempted.
public enum HelperSignatureError: Error, Equatable, Sendable {
    case invalidIdentifier, invalidTeamIdentifier, invalidDevelopmentHash, invalidExecutableURL
    case identityMismatch, invalidSigningInformation
    case securityFailure(operation: HelperSignatureOperation, status: Int32, description: String?)
}

/// A caller-trusted policy, never inferred from the candidate executable's own signing facts.
public enum HelperSignaturePolicy: Equatable, Sendable {
    /// Requires an Apple-anchored signature, exact identifier and exact ten-character signing team.
    /// This is not a Developer ID/notarization or distribution-entitlement check.
    case signedTeam(identifier: String, teamIdentifier: String)
    /// Explicit local-development opt-in to a caller-trusted, 20-byte CDHash; no production fallback.
    case developmentAdHoc(codeDirectoryHash: [UInt8])

    /// Validates configuration and compares already-authenticated facts.
    /// - Parameter identity: Independent facts from the platform boundary (or synthetic test values).
    /// - Throws: `HelperSignatureError` for invalid policy or mismatched identity.
    /// Pure comparison cannot establish code integrity, Apple anchoring or launch-time identity.
    public func validate(_ identity: HelperSignatureIdentity) throws {
        _ = try requirementExpression()
        switch self {
        case .signedTeam(let identifier, let team):
            guard !identity.isAdHoc, identity.identifier == identifier, identity.teamIdentifier == team else {
                throw HelperSignatureError.identityMismatch
            }
        case .developmentAdHoc(let hash):
            guard identity.isAdHoc, identity.teamIdentifier == nil, identity.codeDirectoryHash == hash else {
                throw HelperSignatureError.identityMismatch
            }
        }
    }

    func requirementExpression() throws -> String {
        switch self {
        case .signedTeam(let identifier, let team):
            try Self.validateIdentifier(identifier)
            guard team.utf8.count == 10,
                team.utf8.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) })
            else { throw HelperSignatureError.invalidTeamIdentifier }
            return
                "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
        case .developmentAdHoc(let hash):
            guard hash.count == 20 else { throw HelperSignatureError.invalidDevelopmentHash }
            let digits = Array("0123456789abcdef".utf8)
            let hex = hash.flatMap { [digits[Int($0 >> 4)], digits[Int($0 & 15)]] }
            return "cdhash H\"\(String(decoding: hex, as: UTF8.self))\""
        }
    }
    static func validateIdentifier(_ identifier: String) throws {
        guard !identifier.isEmpty, identifier.utf8.count <= 255,
            identifier.utf8.allSatisfy({ byte in
                (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte)
                    || byte == 45 || byte == 46
            })
        else { throw HelperSignatureError.invalidIdentifier }
    }

}
