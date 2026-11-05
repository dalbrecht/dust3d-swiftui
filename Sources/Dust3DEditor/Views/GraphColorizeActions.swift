/// Render-captured context payload, shared by inspector, canvas and native node context menus.
@MainActor struct GraphColorizeActions {
    let canClear: Bool
    let canAutoColor: Bool
    let clear: @MainActor () -> Void
    let autoColor: @MainActor () -> Void

    init(store: EditorStore?) {
        canClear = store?.canClearSelectionColors == true
        canAutoColor = store?.canAutoColorSelection == true
        if let store {
            clear = store.clearSelectionColorsAction()
            autoColor = store.referenceColorAction()
        } else {
            clear = {}
            autoColor = {}
        }
    }
}
