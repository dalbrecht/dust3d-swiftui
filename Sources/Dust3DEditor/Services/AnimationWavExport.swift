import Dust3DEditorModel
import Dust3DKit
import Foundation

/// Chooses and encodes asynchronously, then admits and commits one bounded file on the UI actor.
@MainActor
enum AnimationWavExport {
    static func save(
        sourceURL: URL?, choose: () async throws -> URL?, encode: () async throws -> Data,
        isCurrent: () -> Bool
    ) async throws -> Bool {
        try Task.checkCancellation()
        guard isCurrent(), let destination = try await choose(), isCurrent() else { return false }
        try Task.checkCancellation()
        let bytes = try await encode()
        try Task.checkCancellation()
        guard isCurrent() else { return false }
        guard !bytes.isEmpty, bytes.count <= 44 + AnimationPCMPlayback.maximumSampleCount * MemoryLayout<Int16>.size
        else { throw DocumentExportError.invalidOutput }
        let scoped = destination.startAccessingSecurityScopedResource()
        defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
        let sourceScoped = sourceURL?.startAccessingSecurityScopedResource() ?? false
        defer { if sourceScoped { sourceURL?.stopAccessingSecurityScopedResource() } }
        try DocumentExportFileService.validateDestination(destination, fileExtension: "wav", source: sourceURL)
        try bytes.write(to: destination, options: .atomic)
        return true
    }
}
