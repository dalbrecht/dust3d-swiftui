import Foundation

/// Validate one Finder document without changing its native URL or opening it on the drop callback.
struct EditorDocumentDrop {
    let url: URL

    init?(urls: [URL]) {
        guard urls.count == 1, let url = urls.first, url.isFileURL, !url.hasDirectoryPath else { return nil }
        let host = url.host?.lowercased()
        let path = url.path(percentEncoded: false)
        guard host == nil || host == "" || host == "localhost",
            url.query == nil, url.fragment == nil, path.hasPrefix("/"),
            path.utf8.count <= 4096, !path.utf8.contains(0), url.pathExtension.lowercased() == "ds3"
        else { return nil }
        self.url = url
    }

    @MainActor
    func open(
        using opener: @MainActor (URL) async throws -> Void,
        reportError: @MainActor (Error) -> Void
    ) async {
        do { try await opener(url) } catch { reportError(error) }
    }
}
