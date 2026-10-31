import Darwin
import Dispatch
import Dust3DKit
import Foundation
import os

@main
struct Dust3DExportApplication {
    static func main() async {
        let code = await execute(
            arguments: Array(CommandLine.arguments.dropFirst()),
            directory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true))
        Darwin.exit(code)
    }

    @MainActor
    static func execute(arguments: [String], directory: URL) async -> Int32 {
        let command: ObjExportCommand
        do { command = try ObjExportCommand.parse(arguments, workingDirectory: directory) } catch {
            report(error: error, stage: .arguments)
            return 2
        }
        switch command {
        case .help:
            do {
                try FileHandle.standardOutput.write(contentsOf: Data((ObjExportCommand.helpText + "\n").utf8))
                return 0
            } catch {
                report(error: error, stage: .reporting)
                return 1
            }
        case .export(let input, let output):
            let receiptOutput: FileHandle
            do { receiptOutput = try reserveReceiptOutput() } catch {
                report(error: error, stage: .reporting)
                return 1
            }
            let task = Task {
                try await ObjExportCommandRunner().run(input: input, output: output) { stage in
                    reportProgress(stage)
                }
            }
            let interrupts = ObjExportInterrupts { task.cancel() }
            defer { interrupts.stop() }
            do {
                let receipt = try await task.value
                do {
                    try receiptOutput.write(contentsOf: try json(receipt))
                    return 0
                } catch {
                    report(error: error, stage: .reporting, committed: receipt.destination)
                    return 1
                }
            } catch is CancellationError {
                report(error: CancellationError(), stage: .reading)
                return 130
            } catch let failure as ObjExportCommandFailure {
                report(error: failure.cause, stage: failure.stage)
                return failure.cause is CancellationError ? 130 : 1
            } catch {
                report(error: error, stage: .generating)
                return 1
            }
        }
    }

    /// Process-only stdio ownership: C++ debug output must never share the JSON receipt stream.
    private static func reserveReceiptOutput() throws -> FileHandle {
        fflush(stdout)
        let descriptor = Darwin.dup(STDOUT_FILENO)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        if Darwin.dup2(STDERR_FILENO, STDOUT_FILENO) < 0 {
            let cause = errno
            Darwin.close(descriptor)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(cause))
        }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    private struct Progress: Encodable {
        let event = "progress"
        let stage: ObjExportCommandStage
    }
    private struct Diagnostic: Encodable {
        let event = "error"
        let stage: ObjExportCommandStage
        let message: String
        let nativeStatus: UInt32?
        let committedDestination: String?
    }
    private static func json<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value) + Data([10])
    }
    private static func reportProgress(_ stage: ObjExportCommandStage) {
        do { try FileHandle.standardError.write(contentsOf: try json(Progress(stage: stage))) } catch {
            logDiagnosticFailure(error)
        }
    }
    private static func report(error: any Error, stage: ObjExportCommandStage, committed: String? = nil) {
        let message = error is CancellationError ? "Export cancelled before commit." : error.localizedDescription
        do {
            try FileHandle.standardError.write(
                contentsOf: try json(
                    Diagnostic(
                        stage: stage, message: message,
                        nativeStatus: (error as? MeshLoadingError)?.status, committedDestination: committed)))
        } catch { logDiagnosticFailure(error) }
    }
    private static func logDiagnosticFailure(_ error: any Error) {
        Logger(subsystem: "org.dust3d.export-cli", category: "diagnostics")
            .error("CLI diagnostic output failed; cause=\(error.localizedDescription, privacy: .private)")
    }
}

/// Signal delivery cancels the task; its normal phase/commit contract decides the actual outcome.
@MainActor
final class ObjExportInterrupts {
    private let source: any DispatchSourceSignal
    // SIG_DFL is a valid null handler; preserving it must not implicitly unwrap it.
    private let previous: sig_t?
    init(cancel: @escaping @Sendable () -> Void) {
        previous = Darwin.signal(SIGINT, SIG_IGN)
        source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global(qos: .userInitiated))
        source.setEventHandler(handler: cancel)
        source.resume()
    }
    func stop() {
        source.cancel()
        Darwin.signal(SIGINT, previous)
    }
}
