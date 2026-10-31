import Dust3DKit
import Foundation

enum ObjExportCommandStage: String, Encodable, Sendable { case reading, generating, writing, arguments, reporting }
struct ObjExportCommandFailure: Error, Sendable {
    let stage: ObjExportCommandStage
    let cause: any Error
}
struct ObjExportCommandReceipt: Encodable, Sendable {
    let destination: String
    let byteCount: Int
    let vertexCount: Int
    let triangleCount: Int
    let sourceWarnings: String
}

/// The CLI shares the editor's bounded generation and coordinated atomic file boundary.
struct ObjExportCommandRunner: Sendable {
    private static let files = MeshFileService()
    let read: @Sendable (URL) async throws -> Data
    let exporter: any ObjExporting
    let writer: any ObjExportFileWriting

    init(
        read: @escaping @Sendable (URL) async throws -> Data = ObjExportCommandRunner.readNativeArchive,
        exporter: any ObjExporting = ObjExportService(), writer: any ObjExportFileWriting = ObjExportFileService()
    ) {
        self.read = read
        self.exporter = exporter
        self.writer = writer
    }

    private static func readNativeArchive(_ url: URL) async throws -> Data {
        try await files.readArchive(url: url, maximumBytes: MeshLoader.maximumFileSize)
    }

    func run(input: URL, output: URL, progress: @Sendable (ObjExportCommandStage) -> Void) async throws
        -> ObjExportCommandReceipt
    {
        try Task.checkCancellation()
        progress(.reading)
        let data = try await attempt(.reading) { try await read(input) }
        progress(.generating)
        let generated = try await attempt(.generating) { try await exporter.encode(data: data, options: .init()) }
        progress(.writing)
        let receipt = try await attempt(.writing) { try await writer.write(output: generated, to: output) }
        // A committed writer receipt remains successful after a late cancellation.
        return ObjExportCommandReceipt(
            destination: receipt.destination.path, byteCount: receipt.byteCount,
            vertexCount: generated.vertexCount, triangleCount: generated.triangleCount,
            sourceWarnings: generated.warning)
    }

    private func attempt<Value: Sendable>(
        _ stage: ObjExportCommandStage,
        operation: @Sendable () async throws -> Value
    ) async throws -> Value {
        do {
            try Task.checkCancellation()
            return try await operation()
        } catch { throw ObjExportCommandFailure(stage: stage, cause: error) }
    }
}
