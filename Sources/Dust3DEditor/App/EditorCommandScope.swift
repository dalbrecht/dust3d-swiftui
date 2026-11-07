import Dust3DEditorModel

/// Keep ordinary graph shortcuts out of animation and native text-editing contexts.
enum EditorCommandScope {
    enum SelectAllDestination: Equatable {
        case text
        case components
        case graph
        case unavailable
    }

    static func selectAllDestination(
        nativeTextFocus: Bool, componentSidebarFocus: Bool, animationFocus: Bool
    ) -> SelectAllDestination {
        if nativeTextFocus { return .text }
        if animationFocus { return .unavailable }
        return componentSidebarFocus ? .components : .graph
    }

    static func hasTextEditingFocus(swiftUIFocus: Bool, hasNativeEditor: Bool) -> Bool {
        swiftUIFocus || hasNativeEditor
    }

    static func allowsGraphShortcuts(animationFocus: Bool, nativeTextFocus: Bool) -> Bool {
        !animationFocus && !nativeTextFocus
    }

    static func allowsGraphDelete(animationFocus: Bool, nativeTextFocus: Bool, componentSidebarFocus: Bool) -> Bool {
        allowsGraphShortcuts(animationFocus: animationFocus, nativeTextFocus: nativeTextFocus) && !componentSidebarFocus
    }

    static func routeUndo(hasNativeEditor: Bool, nativeAction: () -> Void, documentAction: () -> Void) {
        if hasNativeEditor { nativeAction() } else { documentAction() }
    }

    static func routeEscape(
        isMovingOrigin: Bool, canCancelExport: Bool, cancelOrigin: () -> Void, cancelExport: () -> Void
    ) {
        if isMovingOrigin { cancelOrigin() } else if canCancelExport { cancelExport() }
    }
}

/// Selection intent from the rendered component sidebar, excluding collapsed rows.
struct ComponentSidebarSelectAllTarget {
    let ids: Set<String>
    let context: CanvasAdjustmentTarget

    init(snapshot: EditorSnapshot, visibleIDs: Set<String>) {
        ids = visibleIDs
        context = CanvasAdjustmentTarget(snapshot: snapshot)
    }
}
