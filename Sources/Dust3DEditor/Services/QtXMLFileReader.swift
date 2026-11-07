import Darwin
import Foundation

/// Reads one chosen regular file off the UI actor and checks the limit against the opened descriptor.
actor QtXMLFileReader {
    enum Failure: LocalizedError {
        case invalidFile, tooLarge

        var errorDescription: String? {
            switch self {
            case .invalidFile: "Choose one local Qt XML file."
            case .tooLarge: "Qt XML files must be at most 16 MiB."
            }
        }
    }

    private static let maximumBytes = 16 * 1024 * 1024

    func read(_ url: URL) throws -> Data {
        try Task.checkCancellation()
        guard url.isFileURL, url.pathExtension.lowercased() == "xml" else { throw Failure.invalidFile }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let descriptor = try url.withUnsafeFileSystemRepresentation { path in
            guard let path else { throw Failure.invalidFile }
            let descriptor = Darwin.open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
            guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            return descriptor
        }
        defer { _ = Darwin.close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw Failure.invalidFile }
        guard info.st_size >= 0, info.st_size <= Self.maximumBytes else { throw Failure.tooLarge }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        var data = Data()
        // Read at most one byte beyond the limit to detect growth after fstat.
        while data.count <= Self.maximumBytes {
            try Task.checkCancellation()
            let remaining = Self.maximumBytes + 1 - data.count
            let chunk = try file.read(upToCount: min(64 * 1024, remaining)) ?? Data()
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        guard data.count <= Self.maximumBytes else { throw Failure.tooLarge }
        try Task.checkCancellation()
        return data
    }
}
