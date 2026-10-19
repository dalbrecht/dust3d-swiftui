import Foundation

enum EditorLaunchError: Error, LocalizedError, Sendable, Equatable {
    case invalidDocumentArgument

    var errorDescription: String? {
        "Use --open-document followed by one absolute local .ds3 file path (at most 4096 UTF-8 bytes)."
    }
}

enum EditorLaunchRequest: Sendable, Equatable {
    case none
    case open(URL)

    init(arguments: [String]) throws(EditorLaunchError) {
        let flags = arguments.indices.dropFirst().filter { arguments[$0] == "--open-document" }
        guard let index = flags.first else {
            self = .none
            return
        }
        guard flags.count == 1, index + 1 < arguments.count else { throw EditorLaunchError.invalidDocumentArgument }
        let path = arguments[index + 1]
        guard path.hasPrefix("/"), path.utf8.count <= 4096, !path.utf8.contains(0) else {
            throw EditorLaunchError.invalidDocumentArgument
        }
        let url = URL(fileURLWithPath: path)
        guard url.pathExtension.lowercased() == "ds3" else { throw EditorLaunchError.invalidDocumentArgument }
        self = .open(url)
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
            request = .failure(.invalidDocumentArgument)
        }
    }

    func openRequestedDocument(
        open: @MainActor (URL) async throws -> Void,
        reportError: @MainActor (Error) -> Void
    ) async {
        guard !hasHandledRequest else { return }
        // Claim before suspension so duplicate lifecycle callbacks cannot open twice.
        hasHandledRequest = true
        do {
            if case .open(let url) = try request.get() { try await open(url) }
        } catch { reportError(error) }
    }
}
