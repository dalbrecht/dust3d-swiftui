import Foundation

/// Format routing over canonical owned encoders; no C++ adapter or engine owner is duplicated.
public struct NativeGeometryExportEncoder: DocumentExportEncoding {
    private let obj: any DocumentExportEncoding
    private let fbx: any DocumentExportEncoding

    /// Construct both format services without invoking native code.
    /// - Example: `DocumentExportFileService(encoder: NativeGeometryExportEncoder())`.
    public init() {
        obj = NativeOBJExportEncoder()
        fbx = NativeFBXExportEncoder()
    }

    init(obj: any DocumentExportEncoding, fbx: any DocumentExportEncoding) {
        self.obj = obj
        self.fbx = fbx
    }

    /// Route the exact captured archive to the requested original procedural format.
    /// - Parameters: archive is immutable source bytes; format selects OBJ or static FBX geometry.
    /// - Returns: Owned format bytes with the original warning.
    /// - Throws: Original selected encoder error or cancellation; never falls back to another format.
    /// - Example: `try await encoder.encode(archive: document.encoded(), format: .fbx)`.
    public func encode(archive: Data, format: DocumentExportFormat) async throws -> DocumentExportArtifact {
        switch format {
        case .obj: try await obj.encode(archive: archive, format: format)
        case .fbx: try await fbx.encode(archive: archive, format: format)
        }
    }
}
