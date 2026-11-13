#if MOTE3D_EXPERIMENTAL_HOLLOW
    import Dust3DDocument
    import Dust3DEditorModel
    import Dust3DKit
    import Dust3DRendering
    import Foundation
    import MachO
    import XCTest

    @testable import Dust3DEditor

    /// Admitted ordinary two-node tube only; material/import/animation routes never reach native code.
    @MainActor final class HollowNativeHistoryTests: XCTestCase {
        func testReviewedCoreGeneratesCavityAndSolidEndpointsWithExactHistoryAndReopen() async throws {
            let original = try Dust3DDocument(
                snapshotXML: Data(
                    """
                    <canvas originX='.5' originY='.5' originZ='.5'>
                    <nodes>
                    <node id='{00000000-0000-4000-8000-000000000011}' partId='{00000000-0000-4000-8000-000000000010}' x='.3' y='0' z='0' radius='.2'/>
                    <node id='{00000000-0000-4000-8000-000000000012}' partId='{00000000-0000-4000-8000-000000000010}' x='.3' y='1' z='0' radius='.3'/>
                    </nodes><edges>
                    <edge id='{00000000-0000-4000-8000-000000000013}' partId='{00000000-0000-4000-8000-000000000010}' from='{00000000-0000-4000-8000-000000000011}' to='{00000000-0000-4000-8000-000000000012}'/>
                    </edges><parts>
                    <part id='{00000000-0000-4000-8000-000000000010}' target='Model' interpolated='false' rounded='false' hollowThickness='0'/>
                    </parts><components>
                    <component id='{00000000-0000-4000-8000-000000000001}' linkDataType='partId' linkData='{00000000-0000-4000-8000-000000000010}' combineMode='Uncombined'/>
                    </components></canvas>
                    """.utf8))
            let id = "{00000000-0000-4000-8000-000000000010}"
            let hollow = try original.applying(.setPartHollowThickness(id: id, thickness: 0.5))
            let endpoint = try hollow.applying(.setPartHollowThickness(id: id, thickness: 1))
            let cleared = try endpoint.applying(.setPartHollowThickness(id: id, thickness: 0))
            let blocked = HollowBlockedServices()
            let store = EditorStore(
                preview: HollowAdmittedPreview(admitted: [
                    original.encoded(), hollow.encoded(), endpoint.encoded(), cleared.encoded(),
                ]),
                materialBaker: blocked, importedMaterialLoader: blocked, sourceMaterialBaker: blocked,
                animationCatalog: blocked)
            defer { store.stop() }
            if let expected = ProcessInfo.processInfo.environment["MOTE3D_EXPECTED_CORE_REVISION"] {
                let identity = try loadedTestIdentity()
                XCTAssertEqual(identity.coreRevision, expected)
                XCTAssertNotNil(identity.coreDigest)
                XCTAssertEqual(identity.coreIsDirty, false)
            }
            await store.load(data: original.encoded())
            try await settle(store)
            let solid = try XCTUnwrap(store.mesh)
            XCTAssertEqual(solid.triangleCount, 16)
            store.selectPart(id)
            try await settle(store)
            try setThickness("0.5", for: id, in: store)
            try await settle(store)
            XCTAssertEqual(store.mesh?.triangleCount, 32)
            XCTAssertEqual(store.snapshot?.document.encoded(), hollow.encoded())
            store.undo()
            try await settle(store)
            assertSolid(try XCTUnwrap(store.mesh), equals: solid)
            XCTAssertEqual(store.snapshot?.document.encoded(), original.encoded())
            store.redo()
            try await settle(store)
            XCTAssertEqual(store.mesh?.triangleCount, 32)
            try setThickness("1", for: id, in: store)
            try await settle(store)
            XCTAssertNil(store.errorMessage)
            assertSolid(try XCTUnwrap(store.mesh), equals: solid)
            XCTAssertEqual(store.snapshot?.document.encoded(), endpoint.encoded())
            store.undo()
            try await settle(store)
            XCTAssertEqual(store.mesh?.triangleCount, 32)
            XCTAssertEqual(store.snapshot?.document.encoded(), hollow.encoded())
            store.redo()
            try await settle(store)
            assertSolid(try XCTUnwrap(store.mesh), equals: solid)
            XCTAssertEqual(store.snapshot?.document.encoded(), endpoint.encoded())
            try setThickness("0", for: id, in: store)
            try await settle(store)
            assertSolid(try XCTUnwrap(store.mesh), equals: solid)
            XCTAssertEqual(store.snapshot?.document.encoded(), cleared.encoded())
            store.undo()
            try await settle(store)
            store.undo()
            try await settle(store)
            XCTAssertEqual(store.snapshot?.document.encoded(), hollow.encoded())
            let retiredTarget = CanvasAdjustmentTarget(snapshot: try XCTUnwrap(store.snapshot))
            await store.load(data: hollow.encoded())
            try await settle(store)
            XCTAssertEqual(store.mesh?.triangleCount, 32)
            XCTAssertEqual(store.snapshot?.document.encoded(), hollow.encoded())
            store.selectPart(id)
            try await settle(store)
            store.setExperimentalHollowThickness(id, value: "1", target: retiredTarget)
            try await settle(store)
            XCTAssertEqual(store.snapshot?.document.encoded(), hollow.encoded())
            XCTAssertFalse(store.canUndo)
            try setThickness("0.5", for: id, in: store)
            try await settle(store)
            XCTAssertFalse(store.canUndo)
            try setThickness("nan", for: id, in: store)
            try await settle(store)
            XCTAssertNotNil(store.errorMessage)
            XCTAssertEqual(store.snapshot?.document.encoded(), hollow.encoded())
            XCTAssertFalse(store.canUndo)
        }

        private func setThickness(_ value: String, for id: String, in store: EditorStore) throws {
            let target = CanvasAdjustmentTarget(snapshot: try XCTUnwrap(store.snapshot))
            store.setExperimentalHollowThickness(id, value: value, target: target)
        }

        private func assertSolid(
            _ mesh: IndexedMesh, equals solid: IndexedMesh, file: StaticString = #filePath, line: UInt = #line
        ) {
            XCTAssertEqual(mesh.indices, solid.indices, file: file, line: line)
            XCTAssertEqual(mesh.vertices.map(\.position), solid.vertices.map(\.position), file: file, line: line)
            XCTAssertEqual(mesh.vertices.map(\.normal), solid.vertices.map(\.normal), file: file, line: line)
        }

        /// XCTest's host is image zero; verify the loaded test image that actually links the native core.
        private func loadedTestIdentity() throws -> BuildIdentityMetadata {
            guard let executable = Bundle(for: Self.self).executableURL?.resolvingSymlinksInPath() else {
                throw HollowAdmissionError.missingTestImage
            }
            for index in 0..<_dyld_image_count() {
                guard let name = _dyld_get_image_name(index),
                    URL(fileURLWithPath: String(cString: name)).resolvingSymlinksInPath() == executable,
                    let header = _dyld_get_image_header(index), header.pointee.magic == MH_MAGIC_64
                else { continue }
                let header64 = UnsafeRawPointer(header).assumingMemoryBound(to: mach_header_64.self)
                var size: UInt = 0
                guard let bytes = getsectiondata(header64, "__TEXT", "__dust3d_build", &size),
                    size > 0, size <= 4096
                else { throw HollowAdmissionError.missingTestImage }
                return try BuildIdentityMetadata(data: Data(bytes: bytes, count: Int(size)))
            }
            throw HollowAdmissionError.missingTestImage
        }

        private func settle(_ store: EditorStore) async throws {
            for _ in 0..<3000 {
                if !store.isWorking && !store.isGenerating && !store.isBakingMaterials { return }
                try await Task.sleep(for: .milliseconds(10))
            }
            throw HollowAdmissionError.timeout
        }
    }

    private enum HollowAdmissionError: Error { case unreviewedInput, timeout, missingTestImage }

    private struct HollowAdmittedPreview: EditorPreviewServing {
        let admitted: Set<Data>
        private let service = EditorPreviewService()
        func generate(_ data: Data, scopeID: UUID) async throws -> EditorPreviewResult {
            guard admitted.contains(data) else { throw HollowAdmissionError.unreviewedInput }
            return try await service.generate(data, scopeID: scopeID)
        }
        func reset(scopeID: UUID) async throws { try await service.reset(scopeID: scopeID) }
    }

    private struct HollowBlockedServices: ArchiveTextureBaking, ArchiveSourceTextureBaking,
        ArchiveImportedMaterialLoading, AnimationCatalogLoading
    {
        func load(data: Data, options: MeshBakeOptions, limits: ArchiveTextureLimits) async throws
            -> MeshWithBakedTextures
        {
            throw CancellationError()
        }
        func load(data: Data, options: SourceMeshBakeOptions, limits: ArchiveSourceTextureLimits) async throws
            -> SourceBakedMesh
        {
            throw CancellationError()
        }
        func loadIfPresent(data: Data, limits: ImportedMaterialRenderLimits) async throws -> ImportedMaterialRenderData?
        { nil }
        func load() async throws -> AnimationAuthoringCatalog { throw CancellationError() }
    }
#endif
