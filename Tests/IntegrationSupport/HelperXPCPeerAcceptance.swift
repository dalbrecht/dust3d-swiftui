import Darwin
import Foundation

@objc protocol AcceptanceEcho {
    func echo(_ data: Data, withReply reply: @escaping @Sendable (Data) -> Void)
}

final class EchoObject: NSObject, AcceptanceEcho {
    func echo(_ data: Data, withReply reply: @escaping @Sendable (Data) -> Void) { reply(data) }
}

final class EchoListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let lock = NSLock()
    private var count = 0
    var acceptedConnections: Int { lock.withLock { count } }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        lock.withLock { count += 1 }
        connection.exportedInterface = NSXPCInterface(with: AcceptanceEcho.self)
        connection.exportedObject = EchoObject()
        connection.resume()
        return true
    }
}

final class EchoOutcome: @unchecked Sendable {
    enum Result {
        case reply(Data)
        case rejected(String)
        case invalidated
    }
    private let lock = NSLock()
    private let ready = DispatchSemaphore(value: 0)
    private var result: Result?

    func finish(_ value: Result) {
        lock.lock()
        guard result == nil else {
            lock.unlock()
            return
        }
        result = value
        lock.unlock()
        ready.signal()
    }

    func wait() throws -> Result {
        guard ready.wait(timeout: .now() + 10) == .success else { throw AcceptanceFailure.timedOut }
        lock.lock()
        defer { lock.unlock() }
        guard let result else { throw AcceptanceFailure.missingOutcome }
        return result
    }
}

enum AcceptanceFailure: Error {
    case arguments, missingProxy, timedOut, missingOutcome, acceptedWrongPeer
    case missingReply(String)
}

@main
struct HelperXPCPeerAcceptance {
    static func main() {
        do { try run() } catch {
            FileHandle.standardError.write(Data("XPC acceptance failed: \(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    static func run() throws {
        guard CommandLine.arguments.count == 2 else { throw AcceptanceFailure.arguments }
        let digits = Array(CommandLine.arguments[1].utf8)
        guard digits.count == 40 else { throw AcceptanceFailure.arguments }
        let hash = try stride(from: 0, to: digits.count, by: 2).map { offset -> UInt8 in
            guard let value = UInt8(String(decoding: digits[offset..<(offset + 2)], as: UTF8.self), radix: 16) else {
                throw AcceptanceFailure.arguments
            }
            return value
        }
        // Only this test process derives a pin from its own freshly compiled fixture.
        // Production policy must come from independently trusted configuration.
        let policy = HelperSignaturePolicy.developmentAdHoc(codeDirectoryHash: hash)
        _ = try HelperCodeSignatureVerifier().verify(
            executableURL: URL(fileURLWithPath: CommandLine.arguments[0]), policy: policy)
        let factory = HelperXPCPeerFactory()
        let listener = try factory.makeAnonymousListener(policy: policy)
        let delegate = EchoListenerDelegate()
        listener.delegate = delegate
        listener.resume()
        defer { listener.invalidate() }
        let payload = Data([0, 255, 42])
        try withExtendedLifetime(delegate) {
            let matching = try factory.makeEndpointConnection(endpoint: listener.endpoint, policy: policy)
            defer { matching.invalidate() }
            let matchingOutcome = try exchange(matching, payload: payload)
            guard case .reply(let data) = matchingOutcome, data == payload else {
                throw AcceptanceFailure.missingReply(String(describing: matchingOutcome))
            }
            let wrong = HelperSignaturePolicy.developmentAdHoc(codeDirectoryHash: Array(repeating: 0, count: 20))
            let mismatched = try factory.makeEndpointConnection(endpoint: listener.endpoint, policy: wrong)
            defer { mismatched.invalidate() }
            if case .reply = try exchange(mismatched, payload: payload) {
                throw AcceptanceFailure.acceptedWrongPeer
            }
            let rejectingListener = try factory.makeAnonymousListener(policy: wrong)
            let rejectingDelegate = EchoListenerDelegate()
            rejectingListener.delegate = rejectingDelegate
            rejectingListener.resume()
            defer { rejectingListener.invalidate() }
            let rejectedClient = try factory.makeEndpointConnection(
                endpoint: rejectingListener.endpoint, policy: policy)
            defer { rejectedClient.invalidate() }
            try withExtendedLifetime(rejectingDelegate) {
                if case .reply = try exchange(rejectedClient, payload: payload) {
                    throw AcceptanceFailure.acceptedWrongPeer
                }
                guard rejectingDelegate.acceptedConnections == 0 else {
                    throw AcceptanceFailure.acceptedWrongPeer
                }
            }
        }
        print(
            "Matching XPC peer echoed exact bytes; mismatched peer rejected in both directions without engine execution"
        )
    }

    static func exchange(_ connection: NSXPCConnection, payload: Data) throws -> EchoOutcome.Result {
        let outcome = EchoOutcome()
        connection.remoteObjectInterface = NSXPCInterface(with: AcceptanceEcho.self)
        connection.invalidationHandler = { outcome.finish(.invalidated) }
        connection.resume()
        guard
            let proxy = connection.remoteObjectProxyWithErrorHandler({ cause in
                let original = cause as NSError
                outcome.finish(.rejected("\(original.domain) \(original.code): \(original.localizedDescription)"))
            })
                as? AcceptanceEcho
        else { throw AcceptanceFailure.missingProxy }
        proxy.echo(payload) { outcome.finish(.reply($0)) }
        return try outcome.wait()
    }
}
