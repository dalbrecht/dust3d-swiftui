import AppKit
import Observation
import XCTest

@testable import Dust3DEditor

@MainActor
final class NativeUndoCommandStateTests: XCTestCase {
    func testActualUndoManagerChangesInvalidateObservableCommandState() async throws {
        let state = NativeUndoCommandState()
        let manager = UndoManager()
        manager.groupsByEvent = false
        let value = UndoableCommandValue()
        let registration = expectation(description: "registration invalidates observed command state")
        withObservationTracking {
            _ = state.revision
        } onChange: {
            registration.fulfill()
        }
        manager.beginUndoGrouping()
        value.set(1, using: manager)
        manager.endUndoGrouping()
        await fulfillment(of: [registration], timeout: 1)
        XCTAssertTrue(manager.canUndo)
        let beforeUndo = state.revision
        manager.undo()
        for _ in 0..<100 where state.revision == beforeUndo { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertGreaterThan(state.revision, beforeUndo)
        XCTAssertEqual(value.number, 0)
        XCTAssertTrue(manager.canRedo)
        let beforeRedo = state.revision
        manager.redo()
        for _ in 0..<100 where state.revision == beforeRedo { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertGreaterThan(state.revision, beforeRedo)
        XCTAssertEqual(value.number, 1)
        // Drain pending state changes, then prove validation queries do not self-invalidate.
        try await Task.sleep(for: .milliseconds(20))
        let settled = state.revision
        _ = manager.canRedo
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(state.revision, settled)
    }

    func testUndoRedoAndResponderNotificationsInvalidateCommandValidation() async throws {
        let center = NotificationCenter()
        let state = NativeUndoCommandState(center: center)
        for notification in [
            Notification.Name.NSUndoManagerDidCloseUndoGroup, Notification.Name.NSUndoManagerDidUndoChange,
            Notification.Name.NSUndoManagerDidRedoChange,
            NSText.didBeginEditingNotification, NSText.didEndEditingNotification,
            NSText.didChangeNotification, NSTextView.didChangeSelectionNotification,
            NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
        ] {
            let before = state.revision
            center.post(name: notification, object: nil)
            for _ in 0..<100 where state.revision == before {
                try await Task.sleep(for: .milliseconds(5))
            }
            XCTAssertGreaterThan(state.revision, before, notification.rawValue)
        }
    }
}

@MainActor private final class UndoableCommandValue {
    private(set) var number = 0
    func set(_ value: Int, using manager: UndoManager) {
        let previous = number
        manager.registerUndo(withTarget: self) { target in target.set(previous, using: manager) }
        number = value
    }
}
