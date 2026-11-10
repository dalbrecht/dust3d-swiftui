import Foundation

/// Choose the last eligible Finder document and keep its original URL for the native opener.
struct EditorDocumentDrop {
    let url: URL

    init?(urls: [URL]) {
        guard let url = urls.last(where: Self.isLocalDocument) else { return nil }
        self.url = url
    }

    private static func isLocalDocument(_ url: URL) -> Bool {
        guard url.isFileURL, !url.hasDirectoryPath else { return false }
        let host = url.host?.lowercased()
        let path = url.path(percentEncoded: false)
        return (host == nil || host == "" || host == "localhost")
            && url.query == nil && url.fragment == nil && path.hasPrefix("/")
            && path.utf8.count <= 4096 && !path.utf8.contains(0) && url.pathExtension.lowercased() == "ds3"
    }

    @MainActor
    func open(
        using opener: @MainActor (URL) async throws -> Void,
        reportError: @MainActor (Error) -> Void
    ) async {
        do { try await opener(url) } catch { reportError(error) }
    }
}
