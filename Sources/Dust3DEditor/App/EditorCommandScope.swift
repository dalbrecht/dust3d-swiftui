/// Keep ordinary graph shortcuts out of animation and native text-editing contexts.
enum EditorCommandScope {
    static func allowsGraphShortcuts(animationFocus: Bool, nativeTextFocus: Bool) -> Bool {
        !animationFocus && !nativeTextFocus
    }

    static func routeUndo(hasNativeEditor: Bool, nativeAction: () -> Void, documentAction: () -> Void) {
        if hasNativeEditor { nativeAction() } else { documentAction() }
    }
}
