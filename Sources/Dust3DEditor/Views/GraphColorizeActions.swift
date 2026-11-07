/// Render-captured context payload, shared by inspector, canvas and native node context menus.
@MainActor struct GraphColorizeActions {
    let canClear: Bool
    let canAutoColor: Bool
    let clear: @MainActor () -> Void
    let autoColor: @MainActor () -> Void

    init(store: EditorStore?, admitsInput: @escaping @MainActor () -> Bool = { true }) {
        canClear = store?.canClearSelectionColors == true
        canAutoColor = store?.canAutoColorSelection == true
        if let store {
            let clearColors = store.clearSelectionColorsAction()
            let applyColors = store.referenceColorAction()
            clear = { if admitsInput() { clearColors() } }
            autoColor = { if admitsInput() { applyColors() } }
        } else {
            clear = {}
            autoColor = {}
        }
    }
}
