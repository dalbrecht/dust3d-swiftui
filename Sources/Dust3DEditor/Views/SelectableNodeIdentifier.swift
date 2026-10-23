import AppKit
import SwiftUI

/// A read-only identity label that uses the native field editor for selection and clipboard commands.
/// SwiftUI retains the value; AppKit owns only its presentation and transient text selection.
struct SelectableNodeIdentifier: NSViewRepresentable {
    let value: String

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(labelWithString: value)
        field.isSelectable = true
        field.isEditable = false
        field.font = .preferredFont(forTextStyle: .caption1)
        field.textColor = .secondaryLabelColor
        field.lineBreakMode = .byTruncatingMiddle
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        // Keep selection stable during unrelated updates while replacing obsolete identity text.
        if field.stringValue != value { field.stringValue = value }
    }
}
