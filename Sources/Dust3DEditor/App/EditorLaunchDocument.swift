import Foundation

enum EditorLaunchError: Error, LocalizedError, Sendable, Equatable {
    case invalidDocumentArgument
    case unsupportedExportArgument
    case unsupportedPasteArgument
    case unsupportedColorArgument

    var errorDescription: String? {
        switch self {
        case .invalidDocumentArgument:
            "Supply up to 64 distinct local .ds3 paths, each at most 4096 UTF-8 bytes. Paths after --open-document must be absolute."
        case .unsupportedExportArgument:
            "Export at launch is unavailable. Open the document and use File > Export Geometry."
        case .unsupportedPasteArgument:
            "Pasting XML at launch is unavailable. Open the document, copy the node XML, and choose Edit > Paste."
        case .unsupportedColorArgument:
            "Changing model colors at launch is unavailable. Open the document and use Model Colors in the View menu."
        }
    }
}

enum EditorLaunchRequest: Sendable, Equatable {
    case none
    case open([URL])

    init(arguments: [String]) throws(EditorLaunchError) {
        var arguments = arguments.dropFirst()
        var urls: [URL] = []
        var seen = Set<URL>()
        var acceptsPositionals = true
        var parsesOptions = true

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
                case "-o", "-output":
                    throw .unsupportedExportArgument
                case "-paste-xml":
                    throw .unsupportedPasteArgument
                case "-toggle-color":
                    throw .unsupportedColorArgument
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
        self = urls.isEmpty ? .none : .open(urls)
    }
}

/// Delegate file access and window ownership to the native document system, once per launch.
@MainActor
final class EditorLaunchDocumentOpener {
    private let request: Result<EditorLaunchRequest, EditorLaunchError>
    private var hasHandledRequest = false

    var shouldSuppressUntitledDocument: Bool {
        if case .success(.none) = request { return false }
        return true
    }

    init(arguments: [String]) {
        do { request = .success(try EditorLaunchRequest(arguments: arguments)) } catch {
            request = .failure(error)
        }
    }

    func openRequestedDocument(
        open: @MainActor (URL) async throws -> Void,
        reportError: @MainActor (Error) -> Void
    ) async {
        guard !hasHandledRequest else { return }
        // Claim before suspension so duplicate lifecycle callbacks cannot open twice.
        hasHandledRequest = true
        switch request {
        case .success(.none): break
        case .success(.open(let urls)):
            for url in urls {
                do { try await open(url) } catch { reportError(error) }
            }
        case .failure(let error): reportError(error)
        }
    }
}
