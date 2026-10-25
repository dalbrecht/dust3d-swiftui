import Foundation
import Security

/// Narrow read-only macOS static-signature boundary. Performs no launch, signing or trust fallback.
public struct HelperCodeSignatureVerifier: Sendable {
    public init() {}

    /// Checks code integrity and caller-trusted requirements, then copies signing facts.
    /// - Parameters:
    ///   - executableURL: File URL of the candidate helper; stable storage is the caller's responsibility.
    ///   - policy: Trusted expected identity, supplied independently of candidate metadata.
    /// - Returns: Copied facts after strict/all-architecture signature and policy validation.
    /// - Throws: `HelperSignatureError`, preserving original OSStatus/framework causes.
    /// Call away from the UI thread. This proves static validity at inspection time only;
    /// it does not bind a later path-based launch or establish sandbox/notarization acceptance.
    public func verify(executableURL: URL, policy: HelperSignaturePolicy) throws -> HelperSignatureIdentity {
        let expression = try policy.requirementExpression()
        guard executableURL.isFileURL else { throw HelperSignatureError.invalidExecutableURL }
        var code: SecStaticCode?
        try check(
            SecStaticCodeCreateWithPath(executableURL as CFURL, SecCSFlags(), &code), operation: .createCode)
        guard let code else { throw HelperSignatureError.invalidSigningInformation }
        var requirement: SecRequirement?
        try check(
            SecRequirementCreateWithString(expression as CFString, SecCSFlags(), &requirement),
            operation: .createRequirement)
        guard let requirement else { throw HelperSignatureError.invalidSigningInformation }
        var cause: Unmanaged<CFError>?
        let status = SecStaticCodeCheckValidityWithErrors(
            code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures), requirement, &cause)
        let description = cause.map { CFErrorCopyDescription($0.takeRetainedValue()) as String }
        try check(status, operation: .validateCode, description: description)
        var information: CFDictionary?
        try check(
            SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information),
            operation: .readInformation)
        guard let values = information as? [String: Any],
            let identifier = values[kSecCodeInfoIdentifier as String] as? String,
            let hash = values[kSecCodeInfoUnique as String] as? Data,
            let flags = values[kSecCodeInfoFlags as String] as? NSNumber,
            let rawFlags = UInt32(exactly: flags.int64Value)
        else { throw HelperSignatureError.invalidSigningInformation }
        let identity = HelperSignatureIdentity(
            identifier: identifier, teamIdentifier: values[kSecCodeInfoTeamIdentifier as String] as? String,
            codeDirectoryHash: Array(hash), isAdHoc: rawFlags & SecCodeSignatureFlags.adhoc.rawValue != 0)
        try policy.validate(identity)
        return identity
    }

    private func check(
        _ status: OSStatus, operation: HelperSignatureOperation, description: String? = nil
    ) throws {
        guard status == errSecSuccess else {
            let original = description ?? (SecCopyErrorMessageString(status, nil) as String?)
            throw HelperSignatureError.securityFailure(operation: operation, status: status, description: original)
        }
    }
}
