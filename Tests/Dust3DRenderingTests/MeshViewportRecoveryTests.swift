import MetalKit
import XCTest

@testable import Dust3DKit
@testable import Dust3DRendering

@MainActor
final class MeshViewportRecoveryTests: XCTestCase {
    func testFailureReportsOncePerRevisionAndRetriesTheNextRevisionWithoutADevice() async {
        let view = InteractiveMeshView(frame: .zero, device: nil)
        view.isPaused = true
        var reported: [Int] = []
        func update(_ revision: Int) {
            viewport(revision: revision) { reported.append(revision) }.updateRenderer(in: view)
        }
        update(1)
        await drainCallbacks()
        XCTAssertEqual(reported, [1])
        update(1)
        await drainCallbacks()
        XCTAssertEqual(reported, [1])
        update(2)
        await drainCallbacks()
        XCTAssertEqual(reported, [1, 2])
    }

    func testSupersededFailureCallbackIsDiscarded() async {
        let view = InteractiveMeshView(frame: .zero, device: nil)
        view.isPaused = true
        var reported: [Int] = []
        viewport(revision: 1) { reported.append(1) }.updateRenderer(in: view)
        viewport(revision: 2) { reported.append(2) }.updateRenderer(in: view)
        await drainCallbacks()
        XCTAssertEqual(reported, [2])
    }

    func testValidLaterRevisionRecoversAndRetainsTheExistingCamera() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device is available") }
        let view = InteractiveMeshView(frame: .zero, device: nil)
        view.isPaused = true
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        var failures = 0
        viewport(revision: 1) { failures += 1 }.updateRenderer(in: view)
        view.device = device
        viewport(revision: 2) { failures += 1 }.updateRenderer(in: view)
        await drainCallbacks()
        XCTAssertEqual(failures, 0)
        let renderer = try XCTUnwrap(view.renderer)
        renderer.camera.orbit(horizontal: 20, vertical: -10)
        renderer.camera.zoom(delta: 5)
        let camera = renderer.camera
        view.device = nil
        viewport(revision: 3) { failures += 1 }.updateRenderer(in: view)
        await drainCallbacks()
        XCTAssertEqual(failures, 1)
        XCTAssertTrue(view.renderer === renderer)
        view.device = device
        viewport(revision: 4) { failures += 1 }.updateRenderer(in: view)
        XCTAssertEqual(view.meshRevision, 4)
        XCTAssertFalse(view.renderer === renderer)
        XCTAssertEqual(view.renderer?.camera.yaw, camera.yaw)
        XCTAssertEqual(view.renderer?.camera.pitch, camera.pitch)
        XCTAssertEqual(view.renderer?.camera.distance, camera.distance)
    }

    private func viewport(revision: Int, onError: @escaping () -> Void) -> MeshViewport {
        let vertices = [SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0)].map {
            MeshVertex(position: $0, normal: SIMD3(0, 0, 1), color: SIMD4(0.2, 0.4, 0.8, 1))
        }
        let mesh = IndexedMesh(vertices: vertices, indices: [0, 1, 2], nodeCount: 3, partCount: 1, warning: "")
        return MeshViewport(mesh: mesh, isWireframe: false, cameraReset: 0, meshRevision: revision) { _ in onError() }
    }

    private func drainCallbacks() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
