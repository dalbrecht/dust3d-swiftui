import CryptoKit
import Dust3DKit
import Foundation

@testable import Dust3DEditor

/// Every native entry admits only the four archives already audited independently by the root reviewer.
actor ReviewedMultiBindingNative: EditorPreviewServing, ArchiveTextureBaking,
    ArchiveSourceTextureBaking,
    ArchiveImportedMaterialLoading
{
    enum Failure: Error { case unreviewedInput }
    static let expected: [(Int, String)] = [
        (2938, "359f6f9069f1101acddbe9c84dd4714eafe874db6613d1d1e39c4a52902de6a0"),
        (2972, "094f94baf4b4780d82fdecee50de10e294d676284208aa1fd6b2e91dc51fdf11"),
        (2790, "875769d7a4c98230dc5dbfd456d3c67d28a87d133e1f315446df1620e0d8f0e9"),
        (2868, "ff5fb851cc5d59258ce7e35f2f260a46aefdbf9965d6a288664f2b0ee1b4680c"),
    ]
    private let preview = EditorPreviewService()
    private let baker = ArchiveTextureBakingService()
    private let sourceBaker = ArchiveSourceTextureBakingService()
    private let imported = ArchiveImportedMaterialService()

    nonisolated static func admit(_ data: Data) throws {
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard expected.contains(where: { $0.0 == data.count && $0.1 == hash }) else {
            throw Failure.unreviewedInput
        }
    }
    func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult {
        try Self.admit(data)
        return try await preview.generate(data, scopeID: scopeID)
    }
    func reset(scopeID: UUID) async throws { try await preview.reset(scopeID: scopeID) }
    func load(data: Data, options: MeshBakeOptions, limits: ArchiveTextureLimits) async throws
        -> MeshWithBakedTextures
    {
        try Self.admit(data)
        return try await baker.load(data: data, options: options, limits: limits)
    }
    func load(data: Data, options: SourceMeshBakeOptions, limits: ArchiveSourceTextureLimits)
        async throws
        -> SourceBakedMesh
    {
        try Self.admit(data)
        return try await sourceBaker.load(data: data, options: options, limits: limits)
    }
    func loadIfPresent(data: Data, limits: ImportedMaterialRenderLimits) async throws
        -> ImportedMaterialRenderData?
    {
        try Self.admit(data)
        return try await imported.loadIfPresent(data: data, limits: limits)
    }
    func selectForPreparation(
        data: Data, limits: ImportedMaterialRenderLimits, inspectionLimits: ImportedSurfaceOptions
    ) async throws -> ArchiveImportedMaterialSelection {
        try Self.admit(data)
        return try await imported.selectForPreparation(
            data: data, limits: limits, inspectionLimits: inspectionLimits)
    }
}
