import MetalKit
import XCTest

@testable import Dust3DKit
@testable import Dust3DRendering

@MainActor
final class ImportedMaterialViewportTests: XCTestCase {
    func test_should_adopt_imported_output_preserve_camera_and_ignore_detached_gpu_callbacks() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device is available") }
        let view = InteractiveMeshView(frame: .zero, device: device)
        view.isPaused = true
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        let data = try ImportedMetalFixture.quad()
        var errors: [String] = []
        var frames = 0
        func update(_ materials: MeshMaterialContent?, revision: Int, reset: Int = 0) {
            MeshViewport(
                mesh: indexed(data), isWireframe: true, cameraReset: reset, meshRevision: revision,
                materials: materials, onMaterialError: { errors.append($0) }, onMaterialRendered: { frames += 1 },
                onError: { errors.append($0) }
            ).updateRenderer(in: view)
        }
        update(nil, revision: 1)
        view.orbitCamera.orbit(horizontal: 20, vertical: -10)
        update(.imported(data), revision: 1)
        view.orbitCamera.zoom(delta: 4)
        let camera = view.orbitCamera
        await view.materialTask?.value
        XCTAssertEqual(frames, 0)
        XCTAssertNil(view.materialRenderer)
        let renderer = try XCTUnwrap(view.importedRenderer)
        renderer.onRendered?()
        XCTAssertEqual(frames, 1)
        XCTAssertTrue(renderer.isWireframe)
        XCTAssertEqual(view.orbitCamera.yaw, camera.yaw)
        XCTAssertEqual(view.orbitCamera.distance, camera.distance)
        update(nil, revision: 2)
        XCTAssertNil(view.importedRenderer)
        renderer.onRendered?()
        XCTAssertEqual(frames, 1)
        XCTAssertEqual(view.colorPixelFormat, .bgra8Unorm)
        update(.imported(data), revision: 3, reset: 1)
        await view.materialTask?.value
        XCTAssertEqual(view.orbitCamera.yaw, OrbitCamera().yaw)
        XCTAssertTrue(errors.isEmpty)
    }

    func test_should_keep_geometry_on_invalid_imported_upload_and_cancel_replaced_work() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device is available") }
        let view = InteractiveMeshView(frame: .zero, device: device)
        view.isPaused = true
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        let valid = try ImportedMetalFixture.quad()
        let invalid = ImportedMaterialRenderData(surface: valid.surface, materials: [], decodedPayloadBytes: 0)
        var failures: [String] = []
        func update(_ value: MeshMaterialContent?, revision: Int) {
            MeshViewport(
                mesh: indexed(valid), isWireframe: false, cameraReset: 0, meshRevision: revision, materials: value,
                onMaterialError: { failures.append($0) }, onError: { failures.append($0) }
            ).updateRenderer(in: view)
        }
        update(.imported(invalid), revision: 1)
        await view.materialTask?.value
        XCTAssertNotNil(view.renderer)
        XCTAssertNil(view.importedRenderer)
        XCTAssertTrue(view.delegate === view.renderer)
        XCTAssertEqual(failures.count, 1)
        update(.imported(valid), revision: 2)
        let pending = view.materialTask
        update(nil, revision: 3)
        await pending?.value
        XCTAssertNil(view.importedRenderer)
        XCTAssertNil(view.completedMaterialRevision)
    }

    private func indexed(_ data: ImportedMaterialRenderData) -> IndexedMesh {
        IndexedMesh(
            vertices: data.surface.mesh.vertices, indices: data.surface.mesh.vertices.indices.map(UInt32.init),
            nodeCount: 2, partCount: 1, warning: "")
    }
}
