import AppKit
import Dust3DDocument
import SwiftUI

/// Preserve byte-distinct native text edits while SwiftUI owns the accepted draft.
struct ExactBoneNameField: NSViewRepresentable {
    @Binding var name: BoneNameIdentity
    let onSubmit: @MainActor () -> Void
    let onCancel: @MainActor () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: name.rawValue)
        field.placeholderString = "Unassigned"
        field.font = .preferredFont(forTextStyle: .body)
        field.bezelStyle = .roundedBezel
        field.maximumNumberOfLines = 1
        field.cell?.isScrollable = true
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setAccessibilityLabel("Bone name")
        field.setAccessibilityIdentifier("edge-bone-name")
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit(_:))
        field.cell?.sendsActionOnEndEditing = false
        field.isEnabled = context.environment.isEnabled
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.owner = self
        field.isEnabled = context.environment.isEnabled
        let editor = field.currentEditor()
        let current = editor?.string ?? field.stringValue
        // Unrelated publications must retain the native insertion point and selection.
        if !current.utf8.elementsEqual(name.rawValue.utf8) {
            field.stringValue = name.rawValue
            editor?.string = name.rawValue
        }
    }

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var owner: ExactBoneNameField
        init(_ owner: ExactBoneNameField) { self.owner = owner }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField, field.isEnabled else { return }
            owner.name = BoneNameIdentity(field.currentEditor()?.string ?? field.stringValue)
        }

        @objc func submit(_ field: NSTextField) {
            guard field.isEnabled else { return }
            owner.name = BoneNameIdentity(field.currentEditor()?.string ?? field.stringValue)
            owner.onSubmit()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
            owner.onCancel()
            return true
        }
    }
}
