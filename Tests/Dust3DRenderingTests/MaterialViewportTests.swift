import MetalKit
import XCTest

@testable import Dust3DKit
@testable import Dust3DRendering

@MainActor
final class MaterialViewportTests: XCTestCase {
    func testShouldAdoptMaterialsWithoutLosingCameraAndReturnToOrdinaryGeometry() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device is available") }
        let view = InteractiveMeshView(frame: .zero, device: device)
        view.isPaused = true
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        let baked = try BakedMetalFixture.quad()
        var errors: [String] = []
        func update(_ material: MeshWithBakedTextures?, revision: Int = 1, reset: Int = 0) {
            MeshViewport(
                mesh: indexed(baked), isWireframe: true, cameraReset: reset, meshRevision: revision,
                bakedMesh: material, onMaterialError: { errors.append($0) }, onError: { errors.append($0) }
            ).updateRenderer(in: view)
        }
        update(nil)
        view.orbitCamera.orbit(horizontal: 20, vertical: -10)
        view.orbitCamera.zoom(delta: 5)
        let camera = view.orbitCamera
        update(baked)
        // Camera input while the actor is uploading must survive completion.
        view.orbitCamera.orbit(horizontal: 5, vertical: 3)
        let latest = view.orbitCamera
        await view.materialTask?.value
        XCTAssertNotNil(view.materialRenderer)
        XCTAssertEqual(view.colorPixelFormat, .bgra8Unorm_srgb)
        XCTAssertEqual(view.orbitCamera.yaw, latest.yaw)
        XCTAssertNotEqual(latest.yaw, camera.yaw)
        XCTAssertEqual(view.orbitCamera.distance, camera.distance)
        XCTAssertTrue(view.materialRenderer?.isWireframe == true)
        update(nil, revision: 2)
        XCTAssertNil(view.materialRenderer)
        XCTAssertEqual(view.colorPixelFormat, .bgra8Unorm)
        XCTAssertEqual(view.orbitCamera.yaw, latest.yaw)
        update(baked, revision: 3, reset: 1)
        await view.materialTask?.value
        XCTAssertEqual(view.orbitCamera.yaw, OrbitCamera().yaw)
        XCTAssertEqual(view.orbitCamera.distance, OrbitCamera().distance)
        XCTAssertTrue(errors.isEmpty)
    }

    func testShouldDiscardCancelledUploadsAndReleaseDetachedView() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device is available") }
        let baked = try BakedMetalFixture.quad()
        var view: InteractiveMeshView? = InteractiveMeshView(frame: .zero, device: device)
        let target = try XCTUnwrap(view)
        target.isPaused = true
        target.colorPixelFormat = .bgra8Unorm
        target.depthStencilPixelFormat = .depth32Float
        let viewport = MeshViewport(
            mesh: indexed(baked), isWireframe: false, cameraReset: 0, meshRevision: 1,
            bakedMesh: baked, onMaterialError: { _ in XCTFail("Cancelled upload reported a failure") },
            onError: { _ in XCTFail("Ordinary fallback failed") })
        viewport.updateRenderer(in: target)
        let pending = target.materialTask
        target.cancelMaterialUpload()
        await pending?.value
        XCTAssertNil(target.materialRenderer)
        XCTAssertNil(target.requestedMaterialRevision)
        view = nil
    }

    func testShouldReleaseViewWhileAnUploadIsPending() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device is available") }
        let baked = try BakedMetalFixture.quad()
        var view: InteractiveMeshView? = InteractiveMeshView(frame: .zero, device: device)
        weak var reference: InteractiveMeshView?
        reference = view
        var pending: Task<Void, Never>?
        do {
            let target = try XCTUnwrap(view)
            target.isPaused = true
            target.colorPixelFormat = .bgra8Unorm
            target.depthStencilPixelFormat = .depth32Float
            MeshViewport(
                mesh: indexed(baked), isWireframe: false, cameraReset: 0, meshRevision: 1,
                bakedMesh: baked, onError: { _ in XCTFail("Ordinary fallback failed") }
            ).updateRenderer(in: target)
            pending = target.materialTask
        }
        view = nil
        await pending?.value
        XCTAssertNil(reference)
    }

    func testShouldKeepOrdinaryGeometryOnMaterialFailureAndRecoverAtNextRevision() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device is available") }
        let view = InteractiveMeshView(frame: .zero, device: device)
        view.isPaused = true
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        let valid = try BakedMetalFixture.quad()
        let invalid = try BakedMetalFixture.quad(color: BakedMetalFixture.image([]))
        var failures: [String] = []
        func update(_ baked: MeshWithBakedTextures, revision: Int) {
            MeshViewport(
                mesh: indexed(valid), isWireframe: false, cameraReset: 0, meshRevision: revision,
                bakedMesh: baked, onMaterialError: { failures.append($0) },
                onError: { _ in XCTFail("Ordinary fallback failed") }
            ).updateRenderer(in: view)
        }
        update(invalid, revision: 1)
        await view.materialTask?.value
        XCTAssertNotNil(view.renderer)
        XCTAssertNil(view.materialRenderer)
        XCTAssertTrue(view.delegate === view.renderer)
        XCTAssertEqual(failures.count, 1)
        XCTAssertTrue(failures[0].contains("color"))
        update(invalid, revision: 1)
        await view.materialTask?.value
        XCTAssertEqual(failures.count, 1)
        update(valid, revision: 2)
        await view.materialTask?.value
        XCTAssertNotNil(view.materialRenderer)
        XCTAssertEqual(view.completedMaterialRevision, 2)
        XCTAssertEqual(failures.count, 1)
        update(valid, revision: 3)
        let obsolete = view.materialTask
        MeshViewport(
            mesh: indexed(valid), isWireframe: false, cameraReset: 0, meshRevision: 4,
            onError: { _ in XCTFail("Ordinary fallback failed") }
        ).updateRenderer(in: view)
        await obsolete?.value
        XCTAssertNil(view.materialRenderer)
        XCTAssertNil(view.completedMaterialRevision)
        XCTAssertEqual(view.meshRevision, 4)
    }

    func testShouldRequestFirstMaterialFrameWithoutAnotherSwiftUIUpdate() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device is available") }
        let baked = try BakedMetalFixture.quad()
        let view = PresentationMeshView(frame: .zero, device: device)
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        MeshViewport(
            mesh: indexed(baked), isWireframe: false, cameraReset: 0, meshRevision: 1,
            bakedMesh: baked, onError: { _ in XCTFail("Viewport setup failed") }
        ).updateRenderer(in: view)
        let initialRequests = view.drawRequests
        await view.materialTask?.value
        XCTAssertNotNil(view.materialRenderer)
        XCTAssertGreaterThan(view.drawRequests, initialRequests)
    }

    private func indexed(_ baked: MeshWithBakedTextures) -> IndexedMesh {
        IndexedMesh(
            vertices: baked.geometry.vertices, indices: baked.geometry.vertices.indices.map(UInt32.init),
            nodeCount: baked.geometry.nodeCount, partCount: baked.geometry.partCount, warning: "")
    }
}

@MainActor
private final class PresentationMeshView: InteractiveMeshView {
    private(set) var drawRequests = 0
    override func draw() { drawRequests += 1 }
}
