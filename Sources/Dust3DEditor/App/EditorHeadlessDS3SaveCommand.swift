import Darwin
import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation

/// Processes ordered outputs from one owned source archive before the editor creates any windows.
enum EditorHeadlessDS3SaveCommand {
    private static let geometryFBXOption = "--geometry-fbx"
    private static let texturedFBXOption = "--textured-fbx"
    private static let outputOptions = ["-o", "-output", geometryFBXOption, texturedFBXOption]

    private enum OutputKind: String {
        case ds3, obj, fbx, glb
    }

    private enum Failure: LocalizedError {
        case usage
        case unsafeOutput(URL)
        case geometryUnavailable(OutputKind)
        case input(URL, cause: String)
        case fileInspection(URL, code: Int)

        var errorDescription: String? {
            switch self {
            case .usage:
                "Usage: Dust3DEditor [input.ds3] [-paste-xml fragment.xml] -o output.ds3 [-output another ...]. "
                    + "Supply one input archive or XML fragment and up to 64 distinct destinations. "
                    + "Use --geometry-fbx for geometry-only FBX. Ordinary .fbx includes procedural textures."
            case .unsafeOutput(let url):
                "Destination must be a regular file distinct from all inputs and other outputs: \(url.path)"
            case .geometryUnavailable(let kind):
                "Headless .\(kind.rawValue) export is unavailable."
            case .input(let url, let cause):
                "Could not read or apply \(url.path): \(cause)"
            case .fileInspection(let url, let code):
                "Could not inspect \(url.path): \(NSError(domain: NSPOSIXErrorDomain, code: code).localizedDescription)"
            }
        }
    }

    private struct Invocation {
        var source: URL?
        var xml: URL?
        var destinations: [(url: URL, kind: OutputKind, geometryOnly: Bool)] = []

        init(options: ArraySlice<String>) throws {
            var options = options
            var parsesOptions = true
            while let argument = options.popFirst() {
                if parsesOptions, argument == "--" {
                    parsesOptions = false
                } else if parsesOptions, EditorHeadlessDS3SaveCommand.outputOptions.contains(argument) {
                    guard destinations.count < 64 else { throw Failure.usage }
                    let url = try Self.path(options.popFirst())
                    guard let kind = OutputKind(rawValue: url.pathExtension.lowercased()) else { throw Failure.usage }
                    let geometryOnly = argument == EditorHeadlessDS3SaveCommand.geometryFBXOption
                    if geometryOnly || argument == EditorHeadlessDS3SaveCommand.texturedFBXOption {
                        guard kind == .fbx else { throw Failure.usage }
                    }
                    destinations.append((url, kind, geometryOnly))
                } else if parsesOptions, argument == "-paste-xml" {
                    guard xml == nil else { throw Failure.usage }
                    xml = try Self.path(options.popFirst(), extension: "xml")
                } else if parsesOptions, argument == "-toggle-color" {
                    // Qt accepts this display option alongside output. It does not change the source snapshot.
                    guard let operand = options.popFirst(), !operand.hasPrefix("-") else { throw Failure.usage }
                } else if parsesOptions, argument == "--open-document" {
                    guard source == nil, let operand = options.popFirst(), operand.hasPrefix("/") else {
                        throw Failure.usage
                    }
                    source = try Self.path(operand, extension: "ds3")
                } else {
                    guard source == nil else { throw Failure.usage }
                    source = try Self.path(argument, extension: "ds3", allowsLeadingDash: !parsesOptions)
                }
            }
            guard !destinations.isEmpty, source != nil || xml != nil else { throw Failure.usage }
        }

        private static func path(_ argument: String?, extension suffix: String? = nil, allowsLeadingDash: Bool = false)
            throws
            -> URL
        {
            guard let argument, !argument.isEmpty, allowsLeadingDash || !argument.hasPrefix("-"),
                argument.utf8.count <= 4096, !argument.utf8.contains(0),
                argument.hasPrefix("/") || URLComponents(string: argument)?.scheme == nil
            else { throw Failure.usage }
            let url = URL(fileURLWithPath: argument).standardizedFileURL
            if let suffix, url.pathExtension.lowercased() != suffix { throw Failure.usage }
            return url
        }
    }

    private struct FileIdentity: Hashable {
        let device: dev_t
        let inode: ino_t
    }

    /// A nil status leaves the ordinary application and other startup commands in charge.
    @MainActor static func run(
        arguments: [String], geometryEncoder: (any DocumentExportEncoding)? = NativeGeometryExportEncoder(),
        stdout: (String) -> Void, stderr: (String) -> Void
    ) async -> Int32? {
        let options = arguments.dropFirst()
        let switches = options.prefix(while: { $0 != "--" })
        guard EditorLaunchMode(arguments: arguments) == .application, !switches.contains("-list-rigs"),
            switches.contains(where: outputOptions.contains)
        else { return nil }

        let invocation: Invocation
        do {
            invocation = try Invocation(options: options)
            try validateDestinations(invocation)
        } catch {
            stderr(error.localizedDescription + "\n")
            return 2
        }

        let files = DocumentFileService()
        let document: Dust3DDocument
        do {
            document = try await prepareDocument(invocation, files: files)
        } catch {
            stderr(error.localizedDescription + "\n")
            return 1
        }

        let exports = geometryEncoder.map { DocumentExportFileService(encoder: $0) }
        var status: Int32 = 0
        for (destination, kind, geometryOnly) in invocation.destinations {
            do {
                switch kind {
                case .ds3:
                    try await files.save(document, to: destination)
                    stdout("Saved \(destination.path)\n")
                case .obj, .fbx:
                    guard let exports else { throw Failure.geometryUnavailable(kind) }
                    let format: DocumentExportFormat = kind == .obj ? .obj : .fbxTextured
                    let artifact = try await exports.export(
                        document, format: geometryOnly ? .fbx : format, to: destination, sourceURL: invocation.source)
                    stdout("Exported \(destination.path)\n")
                    if !artifact.warning.isEmpty {
                        stderr("Export note for \(destination.path): \(artifact.warning)\n")
                    }
                case .glb:
                    throw Failure.geometryUnavailable(kind)
                }
            } catch {
                status = 1
                let operation = kind == .ds3 ? "save" : "export"
                stderr("Could not \(operation) \(destination.path): \(error.localizedDescription)\n")
            }
        }
        return status
    }

    private static func prepareDocument(_ invocation: Invocation, files: DocumentFileService) async throws
        -> Dust3DDocument
    {
        let original: Dust3DDocument
        if let source = invocation.source {
            do {
                original = try await files.load(from: source)
            } catch { throw Failure.input(source, cause: await EditorStore.message(error)) }
        } else {
            original = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        }
        guard let xml = invocation.xml else { return original }
        do {
            let fragment = try await QtXMLFileReader().read(xml)
            let session = EditorSession()
            let before = try await session.open(data: original.encoded())
            let pasted = try await session.pasteQtXMLFile(fragment, target: .init(snapshot: before))
            guard invocation.source == nil, !pasted.nodes.isEmpty else { return pasted.document }
            return try await session.centerOriginOnModel().document
        } catch { throw Failure.input(xml, cause: await EditorStore.message(error)) }
    }

    private static func validateDestinations(_ invocation: Invocation) throws {
        let inputs = [invocation.source, invocation.xml].compactMap { $0 }.map { $0.resolvingSymlinksInPath() }
        var paths = Set(inputs.map(pathKey))
        var identities = Set(try inputs.compactMap { try fileIdentity($0, isDestination: false) })
        for (destination, _, _) in invocation.destinations {
            guard paths.insert(pathKey(destination)).inserted else { throw Failure.unsafeOutput(destination) }
            if let identity = try fileIdentity(destination, isDestination: true), !identities.insert(identity).inserted
            {
                throw Failure.unsafeOutput(destination)
            }
        }
    }

    private static func pathKey(_ url: URL) -> String {
        let directory = url.deletingLastPathComponent().resolvingSymlinksInPath()
        let path = directory.appendingPathComponent(url.lastPathComponent).path
        let caseSensitive = try? directory.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
            .volumeSupportsCaseSensitiveNames
        return caseSensitive == false ? path.lowercased() : path
    }

    private static func fileIdentity(_ url: URL, isDestination: Bool) throws -> FileIdentity? {
        var metadata = stat()
        let code = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return EINVAL }
            return Darwin.lstat(path, &metadata) == 0 ? 0 : errno
        }
        if code == ENOENT || code == ENOTDIR { return nil }
        guard code == 0 else { throw Failure.fileInspection(url, code: Int(code)) }
        guard metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            if isDestination { throw Failure.unsafeOutput(url) }
            throw Failure.input(url, cause: "Expected a regular file.")
        }
        return FileIdentity(device: metadata.st_dev, inode: metadata.st_ino)
    }
}
