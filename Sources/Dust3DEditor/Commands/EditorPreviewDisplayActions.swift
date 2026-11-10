import SwiftUI

/// Display controls target the visible scene preview and reject obsolete captures.
@MainActor
struct EditorPreviewDisplayActions {
    private let isCurrent: @MainActor () -> Bool
    private let wireframe: @MainActor () -> Bool
    private let writeWireframe: @MainActor (Bool) -> Void
    private let modelColors: (@MainActor () -> Bool)?
    private let writeModelColors: (@MainActor (Bool) -> Void)?

    init(
        isCurrent: @escaping @MainActor () -> Bool = { true },
        wireframe: @escaping @MainActor () -> Bool,
        setWireframe: @escaping @MainActor (Bool) -> Void,
        modelColors: (@MainActor () -> Bool)? = nil,
        setModelColors: (@MainActor (Bool) -> Void)? = nil
    ) {
        self.isCurrent = isCurrent
        self.wireframe = wireframe
        writeWireframe = setWireframe
        self.modelColors = modelColors
        writeModelColors = setModelColors
    }

    /// Apply scene command ownership in addition to the visible preview's own admission.
    func scoped(to ownsMenu: @escaping @MainActor () -> Bool) -> Self {
        Self(
            isCurrent: { ownsMenu() && isCurrent() },
            wireframe: wireframe, setWireframe: writeWireframe,
            modelColors: modelColors, setModelColors: writeModelColors)
    }

    var canChangeWireframe: Bool { isCurrent() }
    var canChangeModelColors: Bool { isCurrent() && modelColors != nil && writeModelColors != nil }
    var isWireframe: Bool { canChangeWireframe && wireframe() }
    var showsModelColors: Bool { canChangeModelColors && modelColors?() == true }

    func setWireframe(_ value: Bool) {
        guard canChangeWireframe else { return }
        writeWireframe(value)
    }

    func setModelColors(_ value: Bool) {
        guard canChangeModelColors else { return }
        writeModelColors?(value)
    }
}

private struct EditorPreviewDisplayActionsKey: FocusedValueKey { typealias Value = EditorPreviewDisplayActions }

extension FocusedValues {
    var editorPreviewDisplayActions: EditorPreviewDisplayActions? {
        get { self[EditorPreviewDisplayActionsKey.self] }
        set { self[EditorPreviewDisplayActionsKey.self] = newValue }
    }
}
