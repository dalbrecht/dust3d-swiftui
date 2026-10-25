import Foundation
import Security

/// Creates suspended XPC objects with explicit peer requirements installed before activation.
/// Caller serializes configuration/lifecycle, supplies interfaces and owns activation/invalidation.
public struct HelperXPCPeerFactory: Sendable {
    public init() {}

    /// Creates a suspended connection to a bundled service with an exact configured name.
    /// - Parameters:
    ///   - serviceName: ASCII bundle-style service name; no discovery or fallback is performed.
    ///   - policy: Caller-trusted expected server identity, enforced by XPC on new messages.
    /// - Returns: Configured connection; set interfaces/handlers before `resume()`.
    /// - Throws: `HelperSignatureError` for invalid policy/name or original Security parser rejection.
    /// Do not set its signing requirement again. This does not launch or prove service packaging.
    public func makeServiceConnection(serviceName: String, policy: HelperSignaturePolicy) throws -> NSXPCConnection {
        try HelperSignaturePolicy.validateIdentifier(serviceName)
        let expression = try checkedExpression(policy)
        let connection = NSXPCConnection(serviceName: serviceName)
        connection.setCodeSigningRequirement(expression)
        return connection
    }

    /// Creates a suspended endpoint connection with a server requirement set exactly once.
    /// - Parameters:
    ///   - endpoint: Endpoint obtained from a trusted source; it is not inferred from reply data.
    ///   - policy: Expected server identity, checked by XPC on the connection rather than a file path.
    /// - Returns: Connection ready for caller interface/handler configuration and activation.
    /// - Throws: `HelperSignatureError` for invalid policy or original Security parser rejection.
    /// Do not replace/reset its signing requirement. No engine protocol or lifecycle is implied.
    public func makeEndpointConnection(
        endpoint: NSXPCListenerEndpoint, policy: HelperSignaturePolicy
    ) throws -> NSXPCConnection {
        let expression = try checkedExpression(policy)
        let connection = NSXPCConnection(listenerEndpoint: endpoint)
        connection.setCodeSigningRequirement(expression)
        return connection
    }

    /// Creates a suspended anonymous listener with its client requirement installed.
    /// - Parameter policy: Expected client identity, checked before consulting the caller's delegate.
    /// - Returns: Anonymous listener; retain/set the delegate before activation and own invalidation.
    /// - Throws: `HelperSignatureError` for invalid policy or original Security parser rejection.
    /// This intentionally does not configure singleton service listeners: Foundation forbids that API.
    public func makeAnonymousListener(policy: HelperSignaturePolicy) throws -> NSXPCListener {
        let expression = try checkedExpression(policy)
        let listener = NSXPCListener.anonymous()
        listener.setConnectionCodeSigningRequirement(expression)
        return listener
    }

    private func checkedExpression(_ policy: HelperSignaturePolicy) throws -> String {
        let expression = try policy.requirementExpression()
        var requirement: SecRequirement?
        let status = SecRequirementCreateWithString(expression as CFString, SecCSFlags(), &requirement)
        guard status == errSecSuccess else {
            throw HelperSignatureError.securityFailure(
                operation: .createRequirement, status: status,
                description: SecCopyErrorMessageString(status, nil) as String?)
        }
        guard requirement != nil else { throw HelperSignatureError.invalidSigningInformation }
        return expression
    }
}
