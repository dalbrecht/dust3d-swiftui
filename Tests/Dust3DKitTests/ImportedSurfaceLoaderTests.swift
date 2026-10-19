import Dust3DDocument
import Dust3DEngine
import Foundation
import XCTest

@testable import Dust3DKit

@MainActor
final class ImportedSurfaceLoaderTests: XCTestCase {
    private func resource(_ name: String = "ImportedSurface") throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "ds3", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    func test_should_copy_aligned_source_uvs_colors_and_catalogs() throws {
        let value = try ImportedSurfaceLoader.load(data: resource())
        XCTAssertEqual(value.mesh.triangleCount, 4)
        XCTAssertEqual(value.triangles.count, value.mesh.triangleCount)
        XCTAssertEqual(value.modelIDs.map(\.id), ["{00000300-0000-4000-8000-000000000300}"])
        XCTAssertEqual(value.components.count, 1)
        XCTAssertEqual(value.components.first?.id, "{00000200-0000-4000-8000-000000000200}")
        XCTAssertEqual(value.components.first?.kind, .original)
        var alphaCounts: [Double: Int] = [:]
        let coordinates = [SIMD2<Double>(0, 0), SIMD2(1, 0), SIMD2(0.5, 1), SIMD2(0.5, 0.5)]
        let colors = [
            SIMD4<Double>(1, 0, 0, 128.0 / 255), SIMD4(0, 1, 0, 1), SIMD4(0, 0, 1, 64.0 / 255),
            SIMD4(1, 1, 0, 192.0 / 255),
        ]
        for triangle in value.triangles {
            XCTAssertEqual(triangle.modelIndex, 0)
            XCTAssertEqual(triangle.componentIndex, 0)
            XCTAssertEqual(triangle.colorEncoding, .linear)
            let uv = try XCTUnwrap(triangle.sourceUVs)
            for (coordinate, color) in zip(
                [uv.first, uv.second, uv.third], [triangle.colors.first, triangle.colors.second, triangle.colors.third])
            {
                let index = try XCTUnwrap(coordinates.firstIndex(of: coordinate))
                XCTAssertEqual(color, colors[index])
                alphaCounts[color.w, default: 0] += 1
            }
        }
        XCTAssertEqual(alphaCounts.count, 4)
        XCTAssertTrue(alphaCounts.values.allSatisfy { $0 == 3 })
        XCTAssertTrue(value.mesh.vertices.allSatisfy { $0.color.w == 1 })
    }

    func test_should_keep_independent_copies_and_enforce_exact_copy_budget() throws {
        var data = try resource()
        let original = data
        let first = try ImportedSurfaceLoader.load(data: data)
        data.resetBytes(in: 0..<data.count)
        _ = try ImportedSurfaceLoader.load(data: original)
        let exact = try ImportedSurfaceLoader.load(
            data: original, options: .init(maximumCopiedPayloadBytes: first.copiedPayloadBytes))
        XCTAssertEqual(exact.triangles, first.triangles)
        XCTAssertThrowsError(
            try ImportedSurfaceLoader.load(
                data: original, options: .init(maximumCopiedPayloadBytes: first.copiedPayloadBytes - 1))
        ) {
            XCTAssertEqual($0 as? ImportedSurfaceError, .copyLimitExceeded)
        }
        let nativeExact = try ImportedSurfaceLoader.load(
            data: original, options: .init(maximumNativePayloadBytes: first.nativePayloadBytes))
        XCTAssertEqual(nativeExact.nativePayloadBytes, first.nativePayloadBytes)
        XCTAssertThrowsError(
            try ImportedSurfaceLoader.load(
                data: original, options: .init(maximumNativePayloadBytes: first.nativePayloadBytes - 1))
        ) {
            XCTAssertTrue($0 is MeshLoadingError)
        }
    }

    func test_should_copy_generated_mirror_catalog_and_corner_alignment() throws {
        let bytes = try resource()
        let start = try XCTUnwrap(bytes.range(of: Data("<canvas".utf8)))
        let end = try XCTUnwrap(bytes.range(of: Data("</canvas>".utf8)))
        let glb = try XCTUnwrap(bytes.range(of: Data("glTF".utf8)))
        let sourceXML = try XCTUnwrap(String(data: bytes[start.lowerBound..<end.upperBound], encoding: .utf8))
        let xml = sourceXML.replacingOccurrences(of: "<part ", with: "<part xMirrored='true' ")
            .replacingOccurrences(of: "<component ", with: "<component combineMode='Uncombined' ")
        let model = Data(xml.utf8)
        let asset = bytes[glb.lowerBound...]
        let prefix = "DUST3D 1.0 xml "
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(model.count)'/><asset name='models/{00000300-0000-4000-8000-000000000300}.glb' offset='\(model.count)' size='\(asset.count)'/></ds3>"
        let offset = prefix.utf8.count + 12 + header.utf8.count
        var archive = Data((prefix + String(format: "%010d", offset) + "\r\n" + header).utf8)
        archive.append(model)
        archive.append(asset)
        let value = try ImportedSurfaceLoader.load(data: archive)
        XCTAssertEqual(value.triangles.count, 8)
        XCTAssertEqual(value.components.filter { $0.kind == .original }.count, 1)
        XCTAssertEqual(value.components.filter { $0.kind == .generated }.count, 1)
        var original = 0
        var generated = 0
        for triangle in value.triangles {
            let index = try XCTUnwrap(triangle.componentIndex)
            if value.components[index].kind == .original { original += 1 } else { generated += 1 }
            XCTAssertEqual(triangle.modelIndex, 0)
            XCTAssertNotNil(triangle.sourceUVs)
            XCTAssertEqual(triangle.colorEncoding, .linear)
        }
        XCTAssertEqual(original, 4)
        XCTAssertEqual(generated, 4)
    }

    func test_should_keep_procedural_sources_explicitly_unmapped() throws {
        let value = try ImportedSurfaceLoader.load(data: resource("Capsule"))
        XCTAssertTrue(value.modelIDs.isEmpty)
        XCTAssertEqual(value.triangles.count, value.mesh.triangleCount)
        XCTAssertTrue(
            value.triangles.allSatisfy { $0.modelIndex == nil && $0.sourceUVs == nil && $0.colorEncoding == .sRGB })
    }
    func test_should_preserve_original_native_errors() throws {
        XCTAssertThrowsError(try ImportedSurfaceLoader.load(data: Data("invalid".utf8))) {
            let error = $0 as? MeshLoadingError
            XCTAssertNotNil(error)
            XCTAssertFalse(error?.message.isEmpty ?? true)
        }
        XCTAssertThrowsError(try ImportedSurfaceLoader.load(data: Dust3DDocument.emptyArchive())) {
            XCTAssertTrue($0 is MeshLoadingError)
        }
    }

    func test_should_preserve_assets_and_source_records_through_edit_undo_and_reopen() throws {
        let data = try resource()
        let original = try Dust3DDocument(data: data)
        var history = DocumentHistory(document: original)
        let id = "{00001000-0000-4000-8000-000000001000}"
        let node = try original.node(id: id)
        try history.apply(.setNode(id: id, position: node.position, radius: 0.2))
        let edited = history.document.encoded()
        let reopened = try Dust3DDocument(data: edited)
        let asset = "models/{00000300-0000-4000-8000-000000000300}.glb"
        XCTAssertEqual(reopened.asset(named: asset), original.asset(named: asset))
        let surface = try ImportedSurfaceLoader.load(data: edited)
        XCTAssertEqual(surface.triangles.count, 4)
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), data)
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.document.encoded(), edited)
        XCTAssertEqual(try ImportedSurfaceLoader.load(data: history.document.encoded()).triangles, surface.triangles)
    }

    func test_should_discard_direct_loader_result_when_cancelled_during_geometry_copy() async throws {
        let data = try resource()
        let task = Task {
            var options = Dust3DImportedSurfaceOptions()
            options.struct_size = MemoryLayout<Dust3DImportedSurfaceOptions>.size
            var error = Dust3DError()
            let owner = try XCTUnwrap(
                data.withUnsafeBytes {
                    dust3d_imported_surface_mesh_load(
                        $0.bindMemory(to: UInt8.self).baseAddress, $0.count, &options, &error)
                })
            defer { dust3d_imported_surface_mesh_destroy(owner) }
            return try ImportedSurfaceCopy.copy(
                owner, options: .init(),
                copyGeometry: { geometry in
                    let mesh = try MeshLoader.copyNativeMesh(geometry)
                    withUnsafeCurrentTask { $0?.cancel() }
                    return mesh
                })
        }
        do {
            _ = try await task.value
            XCTFail("A direct copy cancelled during geometry work must not publish success")
        } catch is CancellationError {}
    }

    func test_should_load_on_background_actor_and_cancel_before_publication() async throws {
        let data = try resource()
        let result = try await ImportedSurfaceService().load(data: data)
        XCTAssertEqual(result.triangles.count, 4)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ImportedSurfaceService().load(data: data)
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled source generation must not publish")
        } catch is CancellationError {}
        let cancelled = ImportedSurfaceService(operation: CancellingSurfaceOperation())
        do {
            _ = try await Task { try await cancelled.load(data: Data()) }.value
            XCTFail("Cancellation during native work must prevent publication")
        } catch is CancellationError {}
        do {
            _ = try await ImportedSurfaceService(operation: FailingSurfaceOperation()).load(data: Data())
            XCTFail("Expected original operation error")
        } catch {
            XCTAssertEqual(error as? SurfaceOperationFailure, .originalCause)
        }
    }

}

private enum SurfaceOperationFailure: Error, Equatable { case originalCause }
private struct FailingSurfaceOperation: ImportedSurfaceOperation {
    func load(data: Data, options: ImportedSurfaceOptions) throws -> ImportedSurfaceMesh {
        throw SurfaceOperationFailure.originalCause
    }
}
private struct CancellingSurfaceOperation: ImportedSurfaceOperation {
    func load(data: Data, options: ImportedSurfaceOptions) throws -> ImportedSurfaceMesh {
        withUnsafeCurrentTask { $0?.cancel() }
        return ImportedSurfaceMesh(
            mesh: Mesh(vertices: [], nodeCount: 0, partCount: 0, warning: ""), triangles: [], modelIDs: [],
            components: [], nativePayloadBytes: 0, copiedPayloadBytes: 0)
    }
}
