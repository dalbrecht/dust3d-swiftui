import AppKit
import SwiftUI

struct AnimationNameText: Equatable {
    let value: String
    init(_ value: String) { self.value = value }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.value.utf8.elementsEqual(rhs.value.utf8) }
}

/// The native field keeps exact text and cursor state; SwiftUI owns the draft and captured target.
struct AnimationNameField: NSViewRepresentable {
    @Binding var text: AnimationNameText
    let onSubmit: @MainActor () -> Void
    let onCancel: @MainActor () -> Void
    var fieldLabel = "Animation name"
    var fieldIdentifier = "animation-name"
    var requestsInitialFocus = true

    static func makeField(_ value: String, requestsInitialFocus: Bool = true) -> NSTextField {
        let field = InitialFocusField(string: value)
        field.shouldRequestFocus = requestsInitialFocus
        field.placeholderString = "Animation name"
        field.font = .preferredFont(forTextStyle: .body)
        field.bezelStyle = .roundedBezel
        field.maximumNumberOfLines = 1
        field.cell?.isScrollable = true
        field.cell?.sendsActionOnEndEditing = false
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setAccessibilityLabel("Animation name")
        field.setAccessibilityIdentifier("animation-name")
        return field
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = Self.makeField(text.value, requestsInitialFocus: requestsInitialFocus)
        field.placeholderString = fieldLabel
        field.setAccessibilityLabel(fieldLabel)
        field.setAccessibilityIdentifier(fieldIdentifier)
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit(_:))
        field.isEnabled = context.environment.isEnabled
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.owner = self
        field.isEnabled = context.environment.isEnabled
        let current = field.currentEditor()?.string ?? field.stringValue
        if !current.utf8.elementsEqual(text.value.utf8) {
            field.stringValue = text.value
            field.currentEditor()?.string = text.value
        }
    }

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var owner: AnimationNameField
        init(_ owner: AnimationNameField) { self.owner = owner }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField, field.isEnabled else { return }
            owner.text = AnimationNameText(field.currentEditor()?.string ?? field.stringValue)
        }
        @objc func submit(_ field: NSTextField) {
            guard field.isEnabled else { return }
            owner.text = AnimationNameText(field.currentEditor()?.string ?? field.stringValue)
            owner.onSubmit()
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
            owner.onCancel()
            return true
        }
    }

    /// Focus only the field's own newly attached window; never activate or find another app/window.
    @MainActor private final class InitialFocusField: NSTextField {
        var shouldRequestFocus = true
        private var requestedFocus = false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard shouldRequestFocus, !requestedFocus, let window else { return }
            requestedFocus = true
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window else { return }
                if window.makeFirstResponder(self) { self.selectText(nil) }
            }
        }
    }
}
