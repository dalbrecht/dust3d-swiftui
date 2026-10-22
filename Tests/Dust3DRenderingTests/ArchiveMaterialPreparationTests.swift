import Foundation
import XCTest

@testable import Dust3DKit
@testable import Dust3DRendering

@MainActor
final class ArchiveMaterialPreparationTests: XCTestCase {
    func testMixedImageAdmissionDoesNotUseImportedOnlyLimits() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Dust3DKitTests/Fixtures")
        let service = ArchiveMaterialPreparationService()
        let options = ArchiveMaterialPreparationOptions(
            imported: ImportedMaterialRenderLimits(maximumEncodedImageBytes: 1))
        let mixed = try Data(contentsOf: root.appendingPathComponent("MixedMaterials.ds3"))
        guard case .sourceBaked = try await service.load(data: mixed, options: options) else {
            return XCTFail("Mixed images must use source admission")
        }
        do {
            _ = try await service.load(
                data: mixed,
                options: ArchiveMaterialPreparationOptions(
                    sourceLimits: ArchiveSourceTextureLimits(
                        textures: ArchiveTextureLimits(maximumEncodedImageBytes: 1))))
            XCTFail("Mixed images must still enforce source admission")
        } catch { XCTAssertEqual(error as? ArchiveTextureBakingError, .encodedLimitExceeded) }
        let procedural = try Data(contentsOf: root.appendingPathComponent("Capsule.ds3"))
        guard case .baked = try await service.load(data: procedural, options: options) else {
            return XCTFail("Procedural archives must retain their own bake path")
        }
        let imported = try Data(contentsOf: root.appendingPathComponent("ImportedSurface.ds3"))
        do {
            _ = try await service.load(data: imported, options: options)
            XCTFail("Pure imported images must still enforce imported admission")
        } catch { XCTAssertEqual(error as? MeshPNGDecodingError, .encodedLimitExceeded) }
    }

    func testChoosesAuthoredImportedOrProceduralBakeWithoutCallingOtherBakers() async throws {
        for hasImported in [false, true] {
            let imported = try importedRenderFixture()
            let baked = try BakedMetalFixture.quad()
            let importer = MaterialPreparationImporter(output: hasImported ? imported : nil)
            let procedural = MaterialPreparationLegacyBaker(output: baked)
            let source = MaterialPreparationSourceBaker(output: BakedMetalFixture.source(baked, policy: nil))
            let service = ArchiveMaterialPreparationService(
                importedLoader: importer, proceduralBaker: procedural, sourceBaker: source)
            let archive = Data([3, 1, 4])
            let result = try await service.load(data: archive, options: .init())
            switch (hasImported, result) {
            case (true, .imported(let value)): XCTAssertEqual(value.surface.modelIDs, imported.surface.modelIDs)
            case (false, .baked(let value)): XCTAssertEqual(value.geometry.triangleCount, baked.geometry.triangleCount)
            default: XCTFail("Incorrect representation")
            }
            let importedInputs = await importer.inputs
            let proceduralInputs = await procedural.inputs
            let sourceInputs = await source.inputs
            XCTAssertEqual(importedInputs, [archive])
            XCTAssertEqual(proceduralInputs, hasImported ? [] : [archive])
            XCTAssertTrue(sourceInputs.isEmpty)
        }
    }

    func testBakesMixedSurfacesFromExactSnapshotWithExplicitSourceQuotas() async throws {
        let baked = try BakedMetalFixture.quad()
        let importer = MaterialPreparationImporter(
            output: try importedRenderFixture(triangleMaterials: [0, nil], depths: [0, 1]))
        let procedural = MaterialPreparationLegacyBaker(output: baked)
        let source = MaterialPreparationSourceBaker(output: BakedMetalFixture.source(baked, policy: nil))
        let service = ArchiveMaterialPreparationService(
            importedLoader: importer, proceduralBaker: procedural, sourceBaker: source)
        let archive = Data([2, 7, 1, 8])
        let options = ArchiveMaterialPreparationOptions(
            source: SourceMeshBakeOptions(maximumChartCount: 7, maximumRasterSamples: 900),
            sourceLimits: ArchiveSourceTextureLimits(textures: ArchiveTextureLimits(maximumDecodedTotalBytes: 24)))
        guard case .sourceBaked = try await service.load(data: archive, options: options) else {
            return XCTFail("Mixed surfaces must use the source-aware bake")
        }
        let sourceInputs = await source.inputs
        let quotas = await source.quotas
        let proceduralInputs = await procedural.inputs
        XCTAssertEqual(sourceInputs, [archive])
        XCTAssertEqual(quotas, [[7, 900, 24]])
        XCTAssertTrue(proceduralInputs.isEmpty)
        XCTAssertEqual(archive, Data([2, 7, 1, 8]))
    }

    func testPreservesOriginalFailuresAtEveryPreparationBoundary() async throws {
        let baked = try BakedMetalFixture.quad()
        for stage in 0..<3 {
            let importer = MaterialPreparationImporter(
                output: stage == 2
                    ? try importedRenderFixture(triangleMaterials: [0, nil], depths: [0, 1]) : nil,
                shouldFail: stage == 0)
            let service = ArchiveMaterialPreparationService(
                importedLoader: importer,
                proceduralBaker: MaterialPreparationLegacyBaker(output: baked, shouldFail: stage == 1),
                sourceBaker: MaterialPreparationSourceBaker(
                    output: BakedMetalFixture.source(baked, policy: nil), shouldFail: stage == 2))
            do {
                _ = try await service.load(data: Data([1]), options: .init())
                XCTFail("Original failure must propagate")
            } catch { XCTAssertEqual(error as? MaterialPreparationFailure, .original) }
        }
    }

    func testPreCancelledRequestDoesNotInspectArchive() async throws {
        let baked = try BakedMetalFixture.quad()
        let importer = MaterialPreparationImporter(output: nil)
        let service = ArchiveMaterialPreparationService(
            importedLoader: importer, proceduralBaker: MaterialPreparationLegacyBaker(output: baked),
            sourceBaker: MaterialPreparationSourceBaker(output: BakedMetalFixture.source(baked, policy: nil)))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.load(data: Data([1]), options: .init())
        }
        do {
            _ = try await task.value
            XCTFail("Pre-cancelled work must not inspect")
        } catch is CancellationError {}
        let inputs = await importer.inputs
        XCTAssertTrue(inputs.isEmpty)
    }

    func testCancelledInspectionCannotStartABakeOrPublishImportedData() async throws {
        let baked = try BakedMetalFixture.quad()
        for mixed in [false, true] {
            let importer = MaterialPreparationImporter(
                output: try importedRenderFixture(
                    triangleMaterials: mixed ? [0, nil] : [0], depths: mixed ? [0, 1] : [0]),
                shouldCancel: true)
            let procedural = MaterialPreparationLegacyBaker(output: baked)
            let source = MaterialPreparationSourceBaker(output: BakedMetalFixture.source(baked, policy: nil))
            let service = ArchiveMaterialPreparationService(
                importedLoader: importer, proceduralBaker: procedural, sourceBaker: source)
            let task = Task { try await service.load(data: Data([1]), options: .init()) }
            do {
                _ = try await task.value
                XCTFail("Cancelled inspection must not publish")
            } catch is CancellationError {}
            let proceduralInputs = await procedural.inputs
            let sourceInputs = await source.inputs
            XCTAssertTrue(proceduralInputs.isEmpty)
            XCTAssertTrue(sourceInputs.isEmpty)
        }
    }
}

private enum MaterialPreparationFailure: Error { case original }

private actor MaterialPreparationImporter: ArchiveImportedMaterialLoading {
    let output: ImportedMaterialRenderData?
    let shouldFail: Bool
    let shouldCancel: Bool
    private(set) var inputs: [Data] = []
    init(output: ImportedMaterialRenderData?, shouldFail: Bool = false, shouldCancel: Bool = false) {
        self.output = output
        self.shouldFail = shouldFail
        self.shouldCancel = shouldCancel
    }
    func loadIfPresent(data: Data, limits: ImportedMaterialRenderLimits) async throws -> ImportedMaterialRenderData? {
        inputs.append(data)
        if shouldFail { throw MaterialPreparationFailure.original }
        if shouldCancel { withUnsafeCurrentTask { $0?.cancel() } }
        return output
    }
}

private actor MaterialPreparationLegacyBaker: ArchiveTextureBaking {
    let output: MeshWithBakedTextures
    let shouldFail: Bool
    private(set) var inputs: [Data] = []
    init(output: MeshWithBakedTextures, shouldFail: Bool = false) {
        self.output = output
        self.shouldFail = shouldFail
    }
    func load(data: Data, options: MeshBakeOptions, limits: ArchiveTextureLimits) async throws -> MeshWithBakedTextures
    {
        inputs.append(data)
        if shouldFail { throw MaterialPreparationFailure.original }
        return output
    }
}

private actor MaterialPreparationSourceBaker: ArchiveSourceTextureBaking {
    let output: SourceBakedMesh
    let shouldFail: Bool
    private(set) var inputs: [Data] = []
    private(set) var quotas: [[Int]] = []
    init(output: SourceBakedMesh, shouldFail: Bool = false) {
        self.output = output
        self.shouldFail = shouldFail
    }
    func load(data: Data, options: SourceMeshBakeOptions, limits: ArchiveSourceTextureLimits) async throws
        -> SourceBakedMesh
    {
        inputs.append(data)
        quotas.append([
            options.maximumChartCount, options.maximumRasterSamples, limits.textures.maximumDecodedTotalBytes,
        ])
        if shouldFail { throw MaterialPreparationFailure.original }
        return output
    }
}
