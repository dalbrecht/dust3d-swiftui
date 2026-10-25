import AppKit
import Combine
import Observation

/// Invalidate SwiftUI command validation when non-observable AppKit editing state changes.
@MainActor @Observable final class NativeUndoCommandState {
    private(set) var revision = 0
    @ObservationIgnored private var observers: [AnyCancellable] = []

    init(center: NotificationCenter = .default) {
        // canRedo itself posts a checkpoint; observing it would create a command-validation loop.
        let notifications: [Notification.Name] = [
            .NSUndoManagerDidCloseUndoGroup, .NSUndoManagerDidUndoChange,
            .NSUndoManagerDidRedoChange,
            NSText.didBeginEditingNotification, NSText.didEndEditingNotification,
            NSText.didChangeNotification, NSTextView.didChangeSelectionNotification,
            NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
        ]
        observers = notifications.map { name in
            center.publisher(for: name).receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.revision &+= 1 }
        }
    }
}
