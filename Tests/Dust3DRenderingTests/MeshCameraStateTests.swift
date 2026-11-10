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
