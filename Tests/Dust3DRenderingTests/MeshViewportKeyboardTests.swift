import AppKit
import XCTest

@testable import Dust3DRendering

@MainActor
final class MeshViewportKeyboardTests: XCTestCase {
    func testModifiedAndUnrelatedKeysReachTheNextResponderWithoutChangingTheCamera() throws {
        let view = InteractiveMeshView(frame: .zero, device: nil)
        let responder = KeyRecorder()
        view.nextResponder = responder
        view.orbitCamera = OrbitCamera(yaw: 0.8, pitch: -0.3, distance: 5)
        let before = view.orbitCamera
        let keys: [(UInt16, String, NSEvent.ModifierFlags)] = [
            (123, "\u{F702}", [.command, .function, .numericPad]),
            (3, "f", .command),
            (124, "\u{F703}", .option),
            (125, "\u{F701}", .shift),
            (126, "\u{F700}", .control),
            (0, "a", []),
        ]

        for (code, characters, modifiers) in keys {
            view.keyDown(with: try key(code, characters, modifiers))
        }

        XCTAssertEqual(responder.codes, keys.map { $0.0 })
        XCTAssertEqual(view.orbitCamera.yaw, before.yaw)
        XCTAssertEqual(view.orbitCamera.pitch, before.pitch)
        XCTAssertEqual(view.orbitCamera.distance, before.distance)
    }

    func testPreviewConsumesUnmodifiedArrowAndFitKeys() throws {
        let view = InteractiveMeshView(frame: .zero, device: nil)
        let responder = KeyRecorder()
        view.nextResponder = responder
        view.orbitCamera = OrbitCamera(yaw: 0.8, pitch: -0.3, distance: 5)

        view.keyDown(with: try key(123, "\u{F702}", [.function, .numericPad]))
        XCTAssertLessThan(view.orbitCamera.yaw, 0.8)
        view.keyDown(with: try key(3, "F", .capsLock))

        XCTAssertTrue(responder.codes.isEmpty)
        XCTAssertEqual(view.orbitCamera.yaw, OrbitCamera().yaw)
        XCTAssertEqual(view.orbitCamera.pitch, OrbitCamera().pitch)
        XCTAssertEqual(view.orbitCamera.distance, OrbitCamera().distance)
    }

    func testDisabledPreviewForwardsCameraKeys() throws {
        let view = InteractiveMeshView(frame: .zero, device: nil)
        let responder = KeyRecorder()
        view.nextResponder = responder
        view.cameraInteractionAllowed = { false }
        let before = view.orbitCamera

        view.keyDown(with: try key(123, "\u{F702}", [.function, .numericPad]))

        XCTAssertEqual(responder.codes, [123])
        XCTAssertEqual(view.orbitCamera.yaw, before.yaw)
    }

    private func key(_ code: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: 0, context: nil, characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: code))
    }

    private final class KeyRecorder: NSResponder {
        var codes: [UInt16] = []

        override func keyDown(with event: NSEvent) {
            codes.append(event.keyCode)
        }
    }
}
