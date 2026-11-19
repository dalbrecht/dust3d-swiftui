import Darwin
import Dust3DEditorModel
import Dust3DKit
import Foundation

/// Publishes one supplied model and its ordered sound sidecars with a partial-result receipt.
@MainActor
enum CombinedAnimationPublication {
    struct Failure {
        let destination: URL
        let cause: any Error
    }

    struct Receipt {
        var published: [URL] = []
        var silent: [String] = []
        var failure: Failure?
    }

    static func save(
        plan: CombinedAnimationExportPlan, modelDestination: URL, sourceURL: URL?,
        isCurrent: () -> Bool, encodeModel: () async throws -> Data,
        encodeWav: (CombinedAnimationExportPlan.Output) async throws -> Data?
    ) async -> Receipt {
        var receipt = Receipt()
        var destination = modelDestination
        let folder = modelDestination.deletingLastPathComponent()
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let sourceScoped = sourceURL?.startAccessingSecurityScopedResource() ?? false
        defer { if sourceScoped { sourceURL?.stopAccessingSecurityScopedResource() } }
        let modelExtension = modelDestination.pathExtension.lowercased()

        func admit() throws {
            try Task.checkCancellation()
            guard isCurrent() else { throw CancellationError() }
        }

        do {
            try admit()
            guard modelExtension == "fbx" || modelExtension == "glb" else {
                throw DocumentExportError.invalidDestination
            }
            try DocumentExportFileService.validateDestination(
                modelDestination, fileExtension: modelExtension, source: sourceURL)
            for output in plan.outputs {
                destination = folder.appendingPathComponent(output.filename)
                try DocumentExportFileService.validateDestination(destination, fileExtension: "wav", source: sourceURL)
                guard !FileManager.default.fileExists(atPath: destination.path) else {
                    throw CocoaError(.fileWriteFileExists)
                }
            }

            destination = modelDestination
            let model = try await encodeModel()
            try admit()
            guard !model.isEmpty, model.count <= 256 * 1024 * 1024 else { throw DocumentExportError.invalidOutput }
            try await publish(model, to: modelDestination, replacing: true) {
                try admit()
                try DocumentExportFileService.validateDestination(
                    modelDestination, fileExtension: modelExtension, source: sourceURL)
            }
            receipt.published.append(modelDestination)

            for output in plan.outputs {
                destination = folder.appendingPathComponent(output.filename)
                try admit()
                let wav = try await encodeWav(output)
                try admit()
                guard let wav else {
                    receipt.silent.append(output.filename)
                    continue
                }
                guard !wav.isEmpty, wav.count <= 44 + AnimationPCMPlayback.maximumSampleCount * MemoryLayout<Int16>.size
                else { throw DocumentExportError.invalidOutput }
                try await publish(wav, to: destination, replacing: false, admit: admit)
                receipt.published.append(destination)
            }
        } catch {
            receipt.failure = Failure(destination: destination, cause: error)
        }
        return receipt
    }

    private static func publish(
        _ bytes: Data, to destination: URL, replacing: Bool, admit: () throws -> Void
    ) async throws {
        let folder = destination.deletingLastPathComponent()
        let staging = folder.appendingPathComponent(".mote-export-\(UUID().uuidString)", isDirectory: true)
        let temporary = staging.appendingPathComponent("payload")
        let worker = Task.detached {
            try Task.checkCancellation()
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
            do {
                try bytes.write(to: temporary)
            } catch {
                try? FileManager.default.removeItem(at: staging)
                throw error
            }
        }
        try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
        defer { try? FileManager.default.removeItem(at: staging) }
        try admit()

        // Same-volume rename is the only publication step. Sidecars never replace a late collision.
        try temporary.withUnsafeFileSystemRepresentation { temporaryPath in
            try destination.withUnsafeFileSystemRepresentation { destinationPath in
                guard let temporaryPath, let destinationPath else { throw DocumentExportError.invalidDestination }
                let result =
                    replacing
                    ? rename(temporaryPath, destinationPath)
                    : renamex_np(temporaryPath, destinationPath, UInt32(RENAME_EXCL))
                guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            }
        }
    }
}
