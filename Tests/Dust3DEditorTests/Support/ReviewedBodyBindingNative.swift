import CryptoKit
import Dust3DKit
import Foundation

@testable import Dust3DEditor

/// Every native entry admits only the four archives already audited independently by the root reviewer.
actor ReviewedBodyBindingNative: EditorPreviewServing, ArchiveTextureBaking, ArchiveSourceTextureBaking,
    ArchiveImportedMaterialLoading
{
    enum Failure: Error { case unreviewedInput }
    static let expected: [(Int, String)] = [
        (2031, "181dc51f15efbae1f14306f0bdc2cae19b910eb7b80f9ea4d7d6c777e3b6da3b"),
        (2065, "7e5952fd359c2b0c90fac97be04a2d833a993d684df354fd27aaba5057564ecb"),
        (1935, "e496fbb1f976b891cd834a79e203aa57668eee2a51807970c137eaaffe82bb09"),
        (2013, "023681501ba133054cdc2cf35877db652426f78eb718f8b0b074654e924f1cbd"),
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
    func load(data: Data, options: MeshBakeOptions, limits: ArchiveTextureLimits) async throws -> MeshWithBakedTextures
    {
        try Self.admit(data)
        return try await baker.load(data: data, options: options, limits: limits)
    }
    func load(data: Data, options: SourceMeshBakeOptions, limits: ArchiveSourceTextureLimits) async throws
        -> SourceBakedMesh
    {
        try Self.admit(data)
        return try await sourceBaker.load(data: data, options: options, limits: limits)
    }
    func loadIfPresent(data: Data, limits: ImportedMaterialRenderLimits) async throws -> ImportedMaterialRenderData? {
        try Self.admit(data)
        return try await imported.loadIfPresent(data: data, limits: limits)
    }
    func selectForPreparation(
        data: Data, limits: ImportedMaterialRenderLimits, inspectionLimits: ImportedSurfaceOptions
    ) async throws -> ArchiveImportedMaterialSelection {
        try Self.admit(data)
        return try await imported.selectForPreparation(data: data, limits: limits, inspectionLimits: inspectionLimits)
    }
}
