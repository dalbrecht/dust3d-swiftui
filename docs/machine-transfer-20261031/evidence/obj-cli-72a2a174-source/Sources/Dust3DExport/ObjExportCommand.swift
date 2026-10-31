import Foundation

enum ObjExportCommand: Sendable {
    case help
    case export(input: URL, output: URL)

    static let helpText = """
        Usage: Dust3DExport INPUT.ds3 --output OUTPUT.obj
               Dust3DExport --input INPUT.ds3 -o OUTPUT.obj

        Exports positions, normals and triangles only. Materials, textures, rigs and
        animation are not included. -o, -output and --output are equivalent.
        Paths may be relative to the current directory. Use -- before a leading-dash
        input filename. One input/output per invocation; unsupported formats fail.
        Success is JSON on stdout; progress/errors are JSON lines on stderr.
        Inherited native debug diagnostics may also appear on stderr.
        Exit codes: 0 success/help, 2 invalid arguments, 1 operation failure, 130 SIGINT.
        """

    static func parse(_ arguments: [String], workingDirectory: URL) throws -> ObjExportCommand {
        if arguments == ["--help"] || arguments == ["-h"] { return .help }
        var input: String?
        var output: String?
        var isLiteral = false
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if !isLiteral && argument == "--" {
                isLiteral = true
                index += 1
                continue
            }
            if !isLiteral && ["--input", "--output", "-output", "-o"].contains(argument) {
                guard index + 1 < arguments.count else { throw ObjExportUsageError("Missing value after \(argument).") }
                index += 1
                if argument == "--input" {
                    guard input == nil else { throw ObjExportUsageError("Specify exactly one input document.") }
                    input = arguments[index]
                } else {
                    guard output == nil else { throw ObjExportUsageError("Specify exactly one output file.") }
                    output = arguments[index]
                }
            } else {
                guard isLiteral || !argument.hasPrefix("-") else {
                    throw ObjExportUsageError("Unknown option: \(argument). Use --help for usage.")
                }
                guard input == nil else { throw ObjExportUsageError("Specify exactly one input document.") }
                input = argument
            }
            index += 1
        }
        guard let input, let output, workingDirectory.isFileURL else {
            throw ObjExportUsageError("An input .ds3 document and output .obj file are required.")
        }
        return .export(
            input: try path(input, extension: "ds3", base: workingDirectory),
            output: try path(output, extension: "obj", base: workingDirectory))
    }

    private static func path(_ value: String, extension suffix: String, base: URL) throws -> URL {
        guard !value.isEmpty, value.utf8.count <= 4096, !value.utf8.contains(0) else {
            throw ObjExportUsageError("Paths must be nonempty, contain no NUL and be at most 4096 UTF-8 bytes.")
        }
        let url = URL(fileURLWithPath: value, relativeTo: base).standardizedFileURL
        guard !url.hasDirectoryPath, url.path.utf8.count <= 4096, url.pathExtension.lowercased() == suffix else {
            throw ObjExportUsageError("Expected a .\(suffix) file path. Only geometry-only OBJ export is supported.")
        }
        return url
    }
}

struct ObjExportUsageError: LocalizedError, Sendable, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
