import AppKit
import XCTest
import simd

@testable import Dust3DKit
@testable import Dust3DRendering

@MainActor
private final class CameraInteractionGate {
    var allowed = true
    var epoch = UUID()
}

@MainActor
final class MeshCameraStateTests: XCTestCase {
    func testOwnedControlsOrbitPanZoomAndFitWithoutLegacyTokens() {
        let owner = MeshCameraState()
        let initial = owner.camera.transform(aspect: 1)
        owner.move(.orbitRight)
        owner.move(.orbitUp)
        owner.move(.panRight)
        owner.move(.panDown)
        owner.move(.zoomIn)
        XCTAssertEqual(owner.revision, 5)
        XCTAssertEqual(owner.camera.yaw, -0.17, accuracy: 0.00001)
        XCTAssertEqual(owner.camera.pitch, -0.03, accuracy: 0.00001)
        XCTAssertLessThan(owner.camera.distance, OrbitCamera().distance)
        XCTAssertNotEqual(owner.camera.transform(aspect: 1), initial)
        owner.fit()
        XCTAssertEqual(owner.revision, 6)
        XCTAssertEqual(owner.camera.transform(aspect: 1), initial)
    }

    func testProjectionInvalidationChangesOnlyInputLease() {
        let owner = MeshCameraState()
        owner.move(.panRight)
        let camera = owner.camera.transform(aspect: 1)
        let revision = owner.revision
        let input = owner.inputRevision
        owner.invalidateProjection()
        XCTAssertNotEqual(owner.inputRevision, input)
        XCTAssertEqual(owner.revision, revision)
        XCTAssertEqual(owner.camera.transform(aspect: 1), camera)
        let next = owner.inputRevision
        owner.invalidateProjection()
        XCTAssertNotEqual(owner.inputRevision, next)
    }

    func testObsoleteProjectionOriginCannotInvalidateCurrentOwnerLease() {
        let owner = MeshCameraState()
        let input = owner.inputRevision
        let revision = owner.revision
        let camera = owner.camera.transform(aspect: 1)
        owner.invalidateProjection(interactionAllowed: { false })
        XCTAssertEqual(owner.inputRevision, input)
        owner.invalidateProjection(interactionAllowed: { true })
        XCTAssertNotEqual(owner.inputRevision, input)
        XCTAssertEqual(owner.revision, revision)
        XCTAssertEqual(owner.camera.transform(aspect: 1), camera)
    }

    func testEveryDiscreteMoveUpdatesOwnedCamera() {
        let owner = MeshCameraState()
        let initial = owner.camera.transform(aspect: 1)
        for action in [
            MeshCameraCommand.Action.orbitLeft, .orbitRight, .orbitUp, .orbitDown,
            .panLeft, .panRight, .panUp, .panDown, .zoomIn, .zoomOut,
        ] {
            let previous = owner.camera.transform(aspect: 1)
            owner.move(action)
            XCTAssertNotEqual(owner.camera.transform(aspect: 1), previous)
        }
        XCTAssertEqual(owner.revision, 10)
        let result = owner.camera.transform(aspect: 1)
        for column in 0..<4 {
            for row in 0..<4 { XCTAssertEqual(result[column][row], initial[column][row], accuracy: 0.00001) }
        }
    }

    func testViewportValuesRetainOwnerAndNeverReplayLegacyInputs() {
        let owner = MeshCameraState()
        owner.move(.panRight)
        let revision = owner.revision
        let moved = owner.camera.transform(aspect: 1)
        let mesh = Mesh(vertices: [], nodeCount: 0, partCount: 0, warning: "")
        let oldCommand = MeshCameraCommand(.orbitRight)
        let first = MeshViewport(
            mesh: mesh, isWireframe: false, cameraReset: 4, cameraCommand: oldCommand,
            cameraState: owner, onError: { _ in })
        let reparented = MeshViewport(
            mesh: mesh, isWireframe: true, cameraReset: 4, cameraCommand: oldCommand,
            cameraState: owner, onError: { _ in })
        XCTAssertTrue(first.cameraState === owner)
        XCTAssertTrue(reparented.cameraState === owner)
        XCTAssertEqual(first.cameraRevision, revision)
        XCTAssertEqual(reparented.cameraRevision, revision)
        XCTAssertEqual(owner.camera.transform(aspect: 1), moved)
        XCTAssertEqual(owner.revision, revision)
        owner.fit()
        let refreshed = MeshViewport(
            mesh: mesh, isWireframe: false, cameraReset: 4, cameraCommand: oldCommand,
            cameraState: owner, onError: { _ in })
        XCTAssertEqual(refreshed.cameraRevision, revision + 1)
        XCTAssertEqual(owner.camera.transform(aspect: 1), OrbitCamera().transform(aspect: 1))
    }

    func testPointerReplacementDoesNotInvalidateObservationAndHonorsInteractionGate() {
        let gate = CameraInteractionGate()
        let owner = MeshCameraState(interactionAllowed: { gate.allowed })
        var pointerCamera = owner.camera
        pointerCamera.orbit(horizontal: 20, vertical: -10)
        pointerCamera.pan(horizontal: 0.25, vertical: -0.1)
        pointerCamera.zoom(delta: 6)
        XCTAssertTrue(owner.replaceFromInteraction(pointerCamera))
        XCTAssertEqual(owner.revision, 0)
        XCTAssertEqual(owner.camera.transform(aspect: 1), pointerCamera.transform(aspect: 1))
        gate.allowed = false
        XCTAssertFalse(owner.replaceFromInteraction(OrbitCamera()))
        XCTAssertEqual(owner.revision, 0)
        XCTAssertEqual(owner.camera.transform(aspect: 1), pointerCamera.transform(aspect: 1))
        // Session-validated controls can reset during a source transition.
        owner.move(.panLeft)
        owner.fit()
        XCTAssertEqual(owner.revision, 2)
        XCTAssertEqual(owner.camera.transform(aspect: 1), OrbitCamera().transform(aspect: 1))
    }

    func testObsoleteViewportOriginCannotWriteNewReadyCamera() {
        let source = CameraInteractionGate()
        let readiness = CameraInteractionGate()
        let owner = MeshCameraState(interactionAllowed: { readiness.allowed })
        let oldEpoch = source.epoch
        let mesh = Mesh(vertices: [], nodeCount: 0, partCount: 0, warning: "")
        let oldViewport = MeshViewport(
            mesh: mesh, isWireframe: false, cameraReset: 0, cameraState: owner,
            cameraInteractionAllowed: { source.epoch == oldEpoch }, onError: { _ in })
        var moved = OrbitCamera()
        moved.orbit(horizontal: 35, vertical: 10)
        XCTAssertTrue(owner.replaceFromInteraction(moved, interactionAllowed: oldViewport.cameraInteractionAllowed))
        source.epoch = UUID()
        owner.fit()
        let current = owner.camera.transform(aspect: 1)
        XCTAssertFalse(oldViewport.cameraInteractionAllowed())
        XCTAssertFalse(owner.replaceFromInteraction(moved, interactionAllowed: oldViewport.cameraInteractionAllowed))
        XCTAssertEqual(owner.camera.transform(aspect: 1), current)
        let currentEpoch = source.epoch
        let currentViewport = MeshViewport(
            mesh: mesh, isWireframe: false, cameraReset: 0, cameraState: owner,
            cameraInteractionAllowed: { source.epoch == currentEpoch }, onError: { _ in })
        readiness.allowed = false
        XCTAssertTrue(currentViewport.cameraInteractionAllowed())
        XCTAssertFalse(
            owner.replaceFromInteraction(moved, interactionAllowed: currentViewport.cameraInteractionAllowed))
        XCTAssertEqual(owner.camera.transform(aspect: 1), current)
        readiness.allowed = true
        XCTAssertTrue(owner.replaceFromInteraction(moved, interactionAllowed: currentViewport.cameraInteractionAllowed))
        XCTAssertEqual(owner.camera.transform(aspect: 1), moved.transform(aspect: 1))
    }

    func testViewportCameraKeysRespectModifiersAdmissionAndKeyboardLayout() throws {
        let view = InteractiveMeshView()
        let initial = view.orbitCamera.transform(aspect: 1)
        func key(_ code: UInt16, characters: String, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try XCTUnwrap(
                NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
                    context: nil, characters: characters, charactersIgnoringModifiers: characters,
                    isARepeat: false, keyCode: code))
        }

        let rightArrow = String(UnicodeScalar(NSRightArrowFunctionKey)!)
        view.keyDown(with: try key(124, characters: rightArrow, modifiers: [.control, .option, .function]))
        XCTAssertEqual(view.orbitCamera.transform(aspect: 1), initial)

        view.cameraInteractionAllowed = { false }
        view.keyDown(with: try key(124, characters: rightArrow, modifiers: [.function]))
        XCTAssertEqual(view.orbitCamera.transform(aspect: 1), initial)

        view.cameraInteractionAllowed = { true }
        view.keyDown(with: try key(124, characters: rightArrow, modifiers: [.function]))
        let orbited = view.orbitCamera.transform(aspect: 1)
        XCTAssertNotEqual(orbited, initial)

        view.keyDown(with: try key(3, characters: "u"))
        XCTAssertEqual(view.orbitCamera.transform(aspect: 1), orbited)
        view.keyDown(with: try key(32, characters: "f"))
        XCTAssertEqual(view.orbitCamera.transform(aspect: 1), initial)
    }

    func testMiddleMouseOrbitsAndShiftPansWithoutPicking() throws {
        let view = InteractiveMeshView(frame: NSRect(x: 0, y: 0, width: 200, height: 200), device: nil)
        var picks = 0
        view.updatePicking(revision: UUID()) { _ in picks += 1 }
        func event(_ type: CGEventType, x: CGFloat, shift: Bool = false, button: CGMouseButton = .center) throws
            -> NSEvent
        {
            let event = try XCTUnwrap(
                CGEvent(
                    mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: x, y: 100),
                    mouseButton: button))
            event.flags = shift ? .maskShift : []
            return try XCTUnwrap(NSEvent(cgEvent: event))
        }

        let initial = view.orbitCamera
        view.otherMouseDown(with: try event(.otherMouseDown, x: 100))
        XCTAssertTrue(view.isDraggingCamera)
        view.mouseDown(with: try event(.leftMouseDown, x: 100, button: .left))
        view.otherMouseDragged(with: try event(.otherMouseDragged, x: 120))
        let orbited = view.orbitCamera
        XCTAssertNotEqual(orbited.yaw, initial.yaw)
        view.otherMouseDragged(with: try event(.otherMouseDragged, x: 140, shift: true))
        XCTAssertEqual(view.orbitCamera.yaw, orbited.yaw)
        XCTAssertNotEqual(view.orbitCamera.transform(aspect: 1), orbited.transform(aspect: 1))
        view.otherMouseUp(with: try event(.otherMouseUp, x: 140))
        XCTAssertFalse(view.isDraggingCamera)
        XCTAssertEqual(picks, 0)

        let finished = view.orbitCamera.transform(aspect: 1)
        view.otherMouseDragged(with: try event(.otherMouseDragged, x: 160))
        view.mouseDragged(with: try event(.leftMouseDragged, x: 160, button: .left))
        view.mouseDragged(with: try event(.leftMouseDragged, x: 180, button: .left))
        XCTAssertEqual(view.orbitCamera.transform(aspect: 1), finished)
        XCTAssertFalse(view.isDraggingCamera)
    }

    func testPreviewWheelPreservesPointerDragAndRespectsCameraAdmission() throws {
        let view = InteractiveMeshView(frame: NSRect(x: 0, y: 0, width: 200, height: 200), device: nil)
        func wheel(vertical: Int32, horizontal: Int32 = 0) throws -> NSEvent {
            let event = try XCTUnwrap(
                CGEvent(
                    scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: vertical,
                    wheel2: horizontal, wheel3: 0))
            return try XCTUnwrap(NSEvent(cgEvent: event))
        }
        func middle(_ type: CGEventType) throws -> NSEvent {
            let event = try XCTUnwrap(
                CGEvent(
                    mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: 100, y: 100),
                    mouseButton: .center))
            return try XCTUnwrap(NSEvent(cgEvent: event))
        }

        let initial = view.orbitCamera.distance
        view.otherMouseDown(with: try middle(.otherMouseDown))
        view.scrollWheel(with: try wheel(vertical: 10))
        XCTAssertTrue(view.isDraggingCamera)
        XCTAssertEqual(view.orbitCamera.distance, initial)
        view.scrollWheel(with: try wheel(vertical: 0, horizontal: 10))
        XCTAssertTrue(view.isDraggingCamera)
        view.otherMouseUp(with: try middle(.otherMouseUp))

        view.cameraInteractionAllowed = { false }
        view.scrollWheel(with: try wheel(vertical: 10))
        XCTAssertEqual(view.orbitCamera.distance, initial)

        view.cameraInteractionAllowed = { true }
        view.scrollWheel(with: try wheel(vertical: 10))
        XCTAssertLessThan(view.orbitCamera.distance, initial)
    }

    func testPointerOrbitRetainsItsDirectionUntilTheNextPressAcrossAPole() throws {
        let view = InteractiveMeshView(frame: NSRect(x: 0, y: 0, width: 200, height: 200), device: nil)
        view.orbitCamera = OrbitCamera(yaw: 0, pitch: 1.5)
        func mouse(_ type: NSEvent.EventType, x: CGFloat, y: CGFloat) throws -> NSEvent {
            try XCTUnwrap(
                NSEvent.mouseEvent(
                    with: type, location: CGPoint(x: x, y: y), modifierFlags: [], timestamp: 0, windowNumber: 0,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }

        view.mouseDown(with: try mouse(.leftMouseDown, x: 100, y: 100))
        view.mouseDragged(with: try mouse(.leftMouseDragged, x: 100, y: 75))
        XCTAssertGreaterThan(view.orbitCamera.pitch, .pi / 2)
        view.mouseDragged(with: try mouse(.leftMouseDragged, x: 120, y: 75))
        XCTAssertGreaterThan(view.orbitCamera.yaw, 0)
        view.mouseUp(with: try mouse(.leftMouseUp, x: 120, y: 75))

        let yaw = view.orbitCamera.yaw
        view.mouseDown(with: try mouse(.leftMouseDown, x: 120, y: 75))
        view.mouseDragged(with: try mouse(.leftMouseDragged, x: 140, y: 75))
        XCTAssertLessThan(view.orbitCamera.yaw, yaw)
        view.mouseUp(with: try mouse(.leftMouseUp, x: 140, y: 75))
    }

    func testEscapeEndsTheActivePreviewPressWithoutPublishingAPick() throws {
        let view = InteractiveMeshView(frame: NSRect(x: 0, y: 0, width: 200, height: 200), device: nil)
        var picks = 0
        view.updatePicking(revision: UUID()) { _ in picks += 1 }
        func mouse(_ type: NSEvent.EventType) throws -> NSEvent {
            try XCTUnwrap(
                NSEvent.mouseEvent(
                    with: type, location: CGPoint(x: 100, y: 100), modifierFlags: [], timestamp: 0, windowNumber: 0,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        let escape = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))

        view.mouseDown(with: try mouse(.leftMouseDown))
        XCTAssertTrue(view.isDraggingCamera)
        let initial = view.orbitCamera.transform(aspect: 1)
        view.keyDown(with: escape)
        XCTAssertFalse(view.isDraggingCamera)
        view.mouseDragged(with: try mouse(.leftMouseDragged))
        view.mouseUp(with: try mouse(.leftMouseUp))
        XCTAssertEqual(picks, 0)
        XCTAssertEqual(view.orbitCamera.transform(aspect: 1), initial)
    }

    func testDefaultExpandedAndIndexedViewportValuesHaveNoOwner() {
        let mesh = Mesh(vertices: [], nodeCount: 0, partCount: 0, warning: "")
        let ordinary = MeshViewport(mesh: mesh, isWireframe: false, cameraReset: 0, onError: { _ in })
        let indexed = IndexedMesh(vertices: [], indices: [], nodeCount: 0, partCount: 0, warning: "")
        let materials = MeshViewport(
            mesh: indexed, isWireframe: false, cameraReset: 0, materials: nil, onError: { _ in })
        XCTAssertNil(ordinary.cameraState)
        XCTAssertNil(ordinary.cameraRevision)
        XCTAssertNil(materials.cameraState)
        XCTAssertNil(materials.cameraRevision)
    }
}
