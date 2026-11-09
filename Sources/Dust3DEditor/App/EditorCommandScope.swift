import Dust3DEditorModel
import Foundation

/// Keep ordinary graph shortcuts out of animation and native text-editing contexts.
enum EditorCommandScope {
    enum SelectAllDestination: Equatable {
        case text
        case components
        case edges
        case nodes
        case graph
        case unavailable
    }

    static func selectAllDestination(
        nativeTextFocus: Bool, componentSidebarFocus: Bool, animationFocus: Bool, edgeSidebarFocus: Bool = false,
        nodesSidebarFocus: Bool = false
    ) -> SelectAllDestination {
        if nativeTextFocus { return .text }
        if animationFocus { return .unavailable }
        if nodesSidebarFocus {
            return componentSidebarFocus || edgeSidebarFocus ? .unavailable : .nodes
        }
        if componentSidebarFocus { return .components }
        return edgeSidebarFocus ? .edges : .graph
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

    enum EscapeDestination: Equatable {
        case system
        case canvas
        case export
        case unavailable
    }

    static func canOfferExportCancellation(hasKeyWindow: Bool, hasSheet: Bool, canCancelExport: Bool) -> Bool {
        hasKeyWindow && !hasSheet && canCancelExport
    }

    static func escapeDestination(
        hasKeyWindow: Bool, hasSheet: Bool, nativeTextFocus: Bool, animationFocus: Bool,
        hasCanvasInput: Bool, canCancelExport: Bool
    ) -> EscapeDestination {
        guard hasKeyWindow else { return .unavailable }
        if hasSheet || nativeTextFocus || animationFocus { return .system }
        if hasCanvasInput { return .canvas }
        return canCancelExport ? .export : .unavailable
    }
}

/// Rendered edge sidebar scope, including its originating rig-mode generation.
struct EdgeSidebarSelectAllTarget {
    let ids: Set<String>
    let context: CanvasAdjustmentTarget
    let rigModeEpoch: UUID
}

/// Selection intent from the rendered component sidebar, excluding collapsed rows.
struct ComponentSidebarSelectAllTarget {
    let ids: Set<String>
    let context: CanvasAdjustmentTarget
    let scopeEpoch: UUID?

    init(snapshot: EditorSnapshot, visibleIDs: Set<String>, scopeEpoch: UUID? = nil) {
        ids = visibleIDs
        context = CanvasAdjustmentTarget(snapshot: snapshot)
        self.scopeEpoch = scopeEpoch
    }
}
