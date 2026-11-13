import SwiftUI

enum EditorInspectorDestination: Equatable {
    case sidebar(Bool)
    case rig
    case animations
}

private struct EditorInspectorNavigationKey: FocusedValueKey {
    typealias Value = @MainActor (EditorInspectorDestination) -> Void
}

private struct EditorSidebarVisibilityKey: FocusedValueKey {
    typealias Value = Bool
}

extension FocusedValues {
    var editorSidebarVisibility: Bool? {
        get { self[EditorSidebarVisibilityKey.self] }
        set { self[EditorSidebarVisibilityKey.self] = newValue }
    }

    var editorInspectorNavigation: (@MainActor (EditorInspectorDestination) -> Void)? {
        get { self[EditorInspectorNavigationKey.self] }
        set { self[EditorInspectorNavigationKey.self] = newValue }
    }
}
