import SwiftUI

enum EditorInspectorDestination: Equatable {
    case sidebar
    case rig
    case animations
}

private struct EditorInspectorNavigationKey: FocusedValueKey {
    typealias Value = @MainActor (EditorInspectorDestination) -> Void
}

extension FocusedValues {
    var editorInspectorNavigation: (@MainActor (EditorInspectorDestination) -> Void)? {
        get { self[EditorInspectorNavigationKey.self] }
        set { self[EditorInspectorNavigationKey.self] = newValue }
    }
}
