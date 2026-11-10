import Dust3DEditorModel
import Foundation

enum EditorLaunchError: Error, LocalizedError, Sendable, Equatable {
    case invalidDocumentArgument
    case unsupportedExportArgument
    case invalidPasteArgument
    case invalidColorArgument

    var errorDescription: String? {
        switch self {
        case .invalidDocumentArgument:
            "Supply up to 64 distinct local .ds3 paths, each at most 4096 UTF-8 bytes. Paths after --open-document must be absolute."
        case .unsupportedExportArgument:
            "Export at launch is unavailable. Open the document and use File > Export Geometry."
        case .invalidPasteArgument:
            "Supply one local XML fragment path after -paste-xml, at most 4096 UTF-8 bytes."
        case .invalidColorArgument:
            "Use -toggle-color followed by true or false, or choose Model Colors in the View menu."
        }
    }
}

enum EditorLaunchRequest: Sendable, Equatable {
    case none
    case untitledPaste(URL)
    case open([URL], hidesPreviewColors: Bool = false, pasteXML: URL? = nil)

    init(arguments: [String]) throws(EditorLaunchError) {
        var arguments = arguments.dropFirst()
        var urls: [URL] = []
        var seen = Set<URL>()
        var acceptsPositionals = true
        var parsesOptions = true
        var hidesPreviewColors = false
        var pasteXML: URL?

        while let argument = arguments.popFirst() {
            let path: String
            let isExplicit = parsesOptions && argument == "--open-document"
            if isExplicit {
                guard let operand = arguments.popFirst() else { throw .invalidDocumentArgument }
                path = operand
            } else if parsesOptions && argument.hasPrefix("-") {
                switch argument {
                case "--":
                    parsesOptions = false
                    acceptsPositionals = true
                case "-o", "-output", "--geometry-fbx", "--textured-fbx":
                    throw .unsupportedExportArgument
                case "-paste-xml":
                    guard pasteXML == nil, let operand = arguments.popFirst(), !operand.isEmpty,
                        !operand.hasPrefix("-"),
                        operand.hasPrefix("/") || URLComponents(string: operand)?.scheme == nil,
                        operand.utf8.count <= 4096, !operand.utf8.contains(0)
                    else { throw .invalidPasteArgument }
                    pasteXML = URL(fileURLWithPath: operand).standardizedFileURL
                case "-toggle-color":
                    guard let operand = arguments.popFirst(), !operand.hasPrefix("-") else {
                        throw .invalidColorArgument
                    }
                    hidesPreviewColors = ["true", "True", "1"].contains(operand)
                case "-ApplePersistenceIgnoreState":
                    if let operand = arguments.first, !operand.hasPrefix("-") { _ = arguments.popFirst() }
                default:
                    // Unknown options may take a path operand. Explicit paths still work.
                    if !argument.hasPrefix("-psn_") { acceptsPositionals = false }
                }
                continue
            } else {
                guard acceptsPositionals, (argument as NSString).pathExtension.lowercased() == "ds3" else {
                    continue
                }
                path = argument
            }

            let isAbsolute = path.hasPrefix("/")
            guard !isExplicit || isAbsolute, isAbsolute || URLComponents(string: path)?.scheme == nil,
                path.utf8.count <= 4096, !path.utf8.contains(0), urls.count < 64
            else { throw .invalidDocumentArgument }
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard url.pathExtension.lowercased() == "ds3", seen.insert(url).inserted else {
                throw .invalidDocumentArgument
            }
            urls.append(url)
        }
        if urls.isEmpty {
            // Qt applies the launch color toggle only to file-backed documents.
            self = pasteXML.map(Self.untitledPaste) ?? .none
        } else {
            self = .open(urls, hidesPreviewColors: hidesPreviewColors, pasteXML: pasteXML)
        }
    }
}

/// Delegate file access and window ownership to the native document system, once per launch.
@MainActor
final class EditorLaunchDocumentOpener {
    private let request: Result<EditorLaunchRequest, EditorLaunchError>
    private var hasHandledRequest = false
    private var neutralPreviewClaims: [URL: LaunchNeutralPreviewClaim] = [:]
    private var startupPasteClaims: [URL?: LaunchStartupPasteClaim] = [:]

    var hasPasteRequest: Bool {
        switch request {
        case .success(.untitledPaste): true
        case .success(.open(_, _, let url)): url != nil
        default: false
        }
    }

    var shouldSuppressUntitledDocument: Bool {
        if case .success(.none) = request { return false }
        return true
    }

    init(arguments: [String]) {
        do { request = .success(try EditorLaunchRequest(arguments: arguments)) } catch {
            request = .failure(error)
        }
    }

    /// A successful open returns the newly created native document, or nil for an existing one.
    func openRequestedDocument(
        readPaste: @MainActor (URL) async throws -> Data = { try await QtXMLFileReader().read($0) },
        open: @MainActor (URL) async throws -> AnyObject?,
        createUntitled: @MainActor () throws -> AnyObject = { throw CocoaError(.featureUnsupported) },
        displayNew: @MainActor (AnyObject) -> Void = { _ in },
        reportError: @MainActor (Error) -> Void
    ) async {
        guard !hasHandledRequest else { return }
        // Claim before suspension so duplicate lifecycle callbacks cannot open twice.
        hasHandledRequest = true
        switch request {
        case .success(.none): break
        case .success(.untitledPaste(let xml)):
            let paste: Result<Data, Error>
            do {
                paste = .success(try await validatedPaste(at: xml, read: readPaste))
            } catch {
                paste = .failure(error)
            }
            guard !Task.isCancelled else { return }
            do {
                let document = try createUntitled()
                if case .success(let data) = paste { registerStartupPaste(data, document: document, source: nil) }
                displayNew(document)
                if case .failure(let error) = paste { reportError(error) }
            } catch {
                reportError(error)
            }
        case .success(.open(let urls, let hidesPreviewColors, let pasteXML)):
            var pasteData: Data?
            var pasteError: Error?
            if let pasteXML {
                do {
                    pasteData = try await validatedPaste(at: pasteXML, read: readPaste)
                } catch {
                    pasteError = error
                }
            }
            for url in urls {
                guard !Task.isCancelled else { return }
                let claim = hidesPreviewColors ? LaunchNeutralPreviewClaim() : nil
                neutralPreviewClaims[url] = claim
                do {
                    let opened = try await open(url)
                    claim?.finish(document: opened)
                    if claim?.document == nil { neutralPreviewClaims[url] = nil }
                    if pasteXML != nil, let opened {
                        if let pasteData, !Task.isCancelled {
                            registerStartupPaste(pasteData, document: opened, source: url)
                        }
                        displayNew(opened)
                    }
                } catch {
                    claim?.finish(document: nil)
                    neutralPreviewClaims[url] = nil
                    reportError(error)
                }
            }
            if let pasteError, !Task.isCancelled { reportError(pasteError) }
        case .failure(let error): reportError(error)
        }
    }

    private func validatedPaste(at url: URL, read: @MainActor (URL) async throws -> Data) async throws -> Data {
        let data = try await read(url)
        try await EditorSession().validateQtXMLFile(data)
        return data
    }

    private func registerStartupPaste(_ data: Data, document: AnyObject, source: URL?) {
        let claim = LaunchStartupPasteClaim(document: document, data: data)
        startupPasteClaims[source] = claim
        let deadline = claim.deadline
        Task { [weak self] in
            try? await Task.sleep(until: deadline, clock: .continuous)
            self?.startupPasteClaims[source] = nil
        }
    }

    func hasStartupPaste(for source: URL?) -> Bool {
        guard let claim = startupPasteClaims[source?.standardizedFileURL] else { return false }
        return ContinuousClock.now < claim.deadline
    }

    /// Retire the matching claim even when the exact document became edited.
    func claimStartupPaste(for source: URL?, document: AnyObject?, isEdited: Bool) -> Data? {
        let url = source?.standardizedFileURL
        guard !Task.isCancelled, let document, let claim = startupPasteClaims[url], claim.document === document
        else { return nil }
        startupPasteClaims[url] = nil
        return isEdited || ContinuousClock.now >= claim.deadline ? nil : claim.data
    }

    /// Consume only for the exact live document created by this launch, after the open result is known.
    func claimNeutralPreview(
        for source: URL?, document: AnyObject?, waitLimit: Duration = .seconds(1)
    ) async -> Bool {
        guard !Task.isCancelled, let url = source?.standardizedFileURL,
            let document, let claim = neutralPreviewClaims[url]
        else { return false }
        await claim.waitForOpen(upTo: waitLimit, document: document)
        guard !Task.isCancelled, claim.document === document, neutralPreviewClaims[url] === claim else {
            return false
        }
        neutralPreviewClaims[url] = nil
        return true
    }
}

private final class LaunchStartupPasteClaim {
    weak var document: AnyObject?
    let data: Data
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))

    init(document: AnyObject, data: Data) {
        self.document = document
        self.data = data
    }
}

@MainActor
private final class LaunchNeutralPreviewClaim {
    private(set) weak var document: AnyObject?
    private var didFinish = false
    private let expiredDocuments = NSHashTable<AnyObject>(options: [.weakMemory, .objectPointerPersonality])
    private var waiters: [UUID: AsyncStream<Void>.Continuation] = [:]

    func finish(document: AnyObject?) {
        self.document = document.flatMap { expiredDocuments.contains($0) ? nil : $0 }
        didFinish = true
        for waiter in waiters.values { waiter.finish() }
        waiters.removeAll()
    }

    private func expire(document: AnyObject) {
        expiredDocuments.add(document)
    }

    func waitForOpen(upTo limit: Duration, document: AnyObject) async {
        guard !didFinish else { return }
        guard limit > .zero else {
            expire(document: document)
            return
        }
        let id = UUID()
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        waiters[id] = continuation
        let deadline = Task { [weak document] in
            do { try await Task.sleep(for: limit) } catch { return }
            guard !Task.isCancelled, !didFinish else { return }
            if let document { expire(document: document) }
            continuation.finish()
        }
        defer { waiters.removeValue(forKey: id)?.finish() }
        await withTaskCancellationHandler {
            var iterator = stream.makeAsyncIterator()
            _ = await iterator.next()
        } onCancel: {
            deadline.cancel()
        }
        deadline.cancel()
    }
}
