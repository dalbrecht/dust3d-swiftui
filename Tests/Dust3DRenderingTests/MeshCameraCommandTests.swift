import Dust3DDocument
import Dust3DKit
import Metal
import XCTest
import simd

@testable import Dust3DRendering

@MainActor final class MeshCameraCommandTests: XCTestCase {
    func testGeometryRendererReplacementPreservesCameraWithoutReplayingPendingCommandAndFitResets() throws {
        for reduceMotion in [false, true] {
            guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device is available") }
            let source = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
                .addNode(
                    id: "{11111111-1111-4111-8111-111111111111}", partID: "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}",
                    componentID: "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}", position: .init(x: 0.5, y: 0.5, z: 0.5),
                    radius: 0.2))
            let mesh = try MeshLoader.loadIndexed(data: source.encoded())
            let view = InteractiveMeshView()
            view.device = device
            view.colorPixelFormat = .bgra8Unorm
            view.depthStencilPixelFormat = .depth32Float
            let command = MeshCameraCommand(.panRight)
            var errors: [String] = []
            func update(revision: Int, reset: Int = 0) {
                MeshViewport(
                    mesh: mesh, isWireframe: false, cameraReset: reset, meshRevision: revision,
                    materials: nil, cameraCommand: command, automaticallyOrbits: true, onError: { errors.append($0) }
                ).updateRenderer(in: view, reduceMotion: reduceMotion)
            }
            update(revision: 1)
            let initialRenderer = try XCTUnwrap(view.renderer)
            let center = SIMD4<Float>(0, 0, 0, 1)
            let panned = view.orbitCamera.transform(aspect: 1) * center
            XCTAssertEqual(panned.x / panned.w, 0.16, accuracy: 0.00001)
            // Pointer zoom after a menu activation must also survive a geometry refresh.
            view.orbitCamera.zoom(delta: 6)
            let currentDistance = view.orbitCamera.distance
            XCTAssertLessThan(currentDistance, OrbitCamera().distance)
            let currentTransform = view.orbitCamera.transform(aspect: 1)
            update(revision: 2)
            XCTAssertFalse(view.renderer === initialRenderer)
            XCTAssertEqual(view.orbitCamera.distance, currentDistance)
            XCTAssertEqual(view.orbitCamera.transform(aspect: 1), currentTransform)
            update(revision: 2, reset: 1)
            XCTAssertEqual(view.orbitCamera.transform(aspect: 1), OrbitCamera().transform(aspect: 1))
            XCTAssertTrue(errors.isEmpty)
            view.cancelMaterialUpload()
        }
    }

    func testDetachedTurntableRemainsStillAndDismantlingReleasesItsView() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device is available") }
        let source = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(
            .addNode(
                id: "{11111111-1111-4111-8111-111111111111}", partID: "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}",
                componentID: "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}", position: .init(x: 0.5, y: 0.5, z: 0.5),
                radius: 0.2))
        let mesh = try MeshLoader.loadIndexed(data: source.encoded())
        var view: InteractiveMeshView? = InteractiveMeshView(frame: .zero, device: device)
        view?.colorPixelFormat = .bgra8Unorm
        view?.depthStencilPixelFormat = .depth32Float
        weak var weakView: InteractiveMeshView?
        weakView = view
        let viewport = MeshViewport(
            mesh: mesh, isWireframe: false, cameraReset: 0, automaticallyOrbits: true, onError: { XCTFail($0) })
        viewport.updateRenderer(in: try XCTUnwrap(view))
        let camera = try XCTUnwrap(view).orbitCamera.transform(aspect: 1)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(view?.orbitCamera.transform(aspect: 1), camera)
        MeshViewport.dismantleNSView(try XCTUnwrap(view), coordinator: ())
        view = nil
        XCTAssertNil(weakView)
    }

    func testForwardedCanvasDragUsesTheMountedCameraAndRetiresOnReset() throws {
        let view = InteractiveMeshView(frame: .init(x: 0, y: 0, width: 400, height: 200), device: nil)
        XCTAssertNil(view.beginCanvasDrag())
        view.meshRevision = 1
        let original = view.orbitCamera
        let token = try XCTUnwrap(view.beginCanvasDrag())
        XCTAssertTrue(view.isDraggingCamera)
        XCTAssertNil(view.beginCanvasDrag())
        XCTAssertTrue(view.updateCanvasDrag(token, by: .init(10, 5), pans: false))
        XCTAssertEqual(view.orbitCamera.yaw, original.yaw + 0.1, accuracy: 0.00001)
        XCTAssertEqual(view.orbitCamera.pitch, original.pitch - 0.05, accuracy: 0.00001)
        XCTAssertTrue(view.updateCanvasDrag(token, by: .init(20, 10), pans: true))
        let clip = view.orbitCamera.transform(aspect: 1) * SIMD4<Float>(0, 0, 0, 1)
        XCTAssertEqual(clip.x / clip.w, 0.1, accuracy: 0.00001)
        XCTAssertEqual(clip.y / clip.w, 0.1, accuracy: 0.00001)
        view.cameraReset += 1
        XCTAssertFalse(view.updateCanvasDrag(token, by: .init(8, 6), pans: false))
        view.endCanvasDrag(token)
        XCTAssertFalse(view.isDraggingCamera)
        let current = try XCTUnwrap(view.beginCanvasDrag())
        view.endCanvasDrag(token)
        XCTAssertTrue(view.isDraggingCamera)
        view.endCanvasDrag(current)
        XCTAssertFalse(view.isDraggingCamera)
    }

    func testActivationIsConsumedOnceAndRepeatingTheActionHasANewIdentity() {
        let view = InteractiveMeshView()
        let command = MeshCameraCommand(.zoomIn)
        view.applyCameraCommand(command)
        let distance = view.orbitCamera.distance
        XCTAssertLessThan(distance, OrbitCamera().distance)
        view.applyCameraCommand(command)
        XCTAssertEqual(view.orbitCamera.distance, distance)
        view.applyCameraCommand(.init(.zoomIn))
        XCTAssertLessThan(view.orbitCamera.distance, distance)
    }

    func testEveryCameraDirectionAndZoomPreservesUnrelatedAxes() {
        for (action, yaw, pitch): (MeshCameraCommand.Action, Float, Float) in [
            (.orbitLeft, -0.18, 0), (.orbitRight, 0.18, 0),
            (.orbitUp, 0, -0.18), (.orbitDown, 0, 0.18),
        ] {
            let view = InteractiveMeshView()
            let initial = view.orbitCamera
            view.applyCameraCommand(.init(action))
            XCTAssertEqual(view.orbitCamera.yaw, initial.yaw + yaw, accuracy: 0.00001)
            XCTAssertEqual(view.orbitCamera.pitch, initial.pitch + pitch, accuracy: 0.00001)
            XCTAssertEqual(view.orbitCamera.distance, initial.distance)
        }
        let view = InteractiveMeshView()
        view.applyCameraCommand(.init(.zoomOut))
        XCTAssertGreaterThan(view.orbitCamera.distance, OrbitCamera().distance)
    }

    func testPanMovesInScreenSpaceAcrossAspectsAndFitRestoresCamera() {
        let view = InteractiveMeshView()
        let center = SIMD4<Float>(0, 0, 0, 1)
        view.applyCameraCommand(.init(.panRight))
        view.applyCameraCommand(.init(.panUp))
        for aspect: Float in [0.5, 1, 2] {
            let clip = view.orbitCamera.transform(aspect: aspect) * center
            XCTAssertEqual(clip.x / clip.w, 0.16, accuracy: 0.00001)
            XCTAssertEqual(clip.y / clip.w, 0.16, accuracy: 0.00001)
        }
        view.applyCameraCommand(.init(.panLeft))
        view.applyCameraCommand(.init(.panDown))
        let centered = view.orbitCamera.transform(aspect: 1) * center
        XCTAssertEqual(centered.x, 0, accuracy: 0.00001)
        XCTAssertEqual(centered.y, 0, accuracy: 0.00001)
        view.applyCameraCommand(.init(.panRight))
        view.orbitCamera = OrbitCamera()
        let fitted = view.orbitCamera.transform(aspect: 1) * center
        XCTAssertEqual(fitted.x, 0)
        XCTAssertEqual(fitted.y, 0)
    }

    func testPanIsBoundedWithoutChangingRotationOrDistance() {
        var camera = OrbitCamera()
        let original = camera
        let center = SIMD4<Float>(0, 0, 0, 1)
        for delta: Float in [100, -100] {
            camera.pan(horizontal: delta, vertical: delta)
            let clip = camera.transform(aspect: 1) * center
            XCTAssertEqual(clip.x / clip.w, delta > 0 ? 1.5 : -1.5, accuracy: 0.00001)
            XCTAssertEqual(clip.y / clip.w, delta > 0 ? 1.5 : -1.5, accuracy: 0.00001)
            XCTAssertEqual(camera.yaw, original.yaw)
            XCTAssertEqual(camera.pitch, original.pitch)
            XCTAssertEqual(camera.distance, original.distance)
        }
    }
}
