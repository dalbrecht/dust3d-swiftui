import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

struct OriginHandle: View {
    let store: EditorStore
    let origin: NodePosition
    let projection: CanvasProjection
    var profileLease: UUID? = nil
    var previewDrag: CanvasPreviewDrag.Begin? = nil
    var precisionKey: ((CanvasPrecisionKeyInput) -> Bool)? = nil
    var switchProfile: ((CanvasProfileFocusRequest) -> Bool)? = nil

    private var ownsProfile: Bool { store.ownsCanvasProfile(profileLease) }

    var body: some View {
        let point = projection.point(for: origin)
        let handlePrecisionKey = precisionKey ?? store.canvasPrecisionKeyHandler()
        let direct = store.directOriginDragAction(projection: projection, lease: profileLease)
        let explicit = store.isMovingOrigin && !store.isWorking
        let enabled = explicit || direct != nil
        let hitSize: CGFloat = explicit ? 44 : 20
        Image(systemName: "scope")
            .font(.title3)
            .foregroundStyle(store.isMovingOrigin || store.originDragPosition != nil ? Color.accentColor : .secondary)
            .frame(width: hitSize, height: hitSize)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Text(store.isMovingOrigin ? "Move Origin · Esc cancels" : "Origin")
                    .font(.caption2).fixedSize().offset(y: 8).allowsHitTesting(false).accessibilityHidden(true)
            }
            .overlay {
                NodePointerSurface(
                    enabled: enabled, canDrag: true,
                    begin: { token in
                        guard ownsProfile else { return }
                        if explicit {
                            store.beginOriginDrag(token: token, projection: projection)
                        } else {
                            direct?(token)
                        }
                    },
                    update: { if ownsProfile { store.updateOriginDrag(token: $0, translation: $1) } },
                    finish: { if ownsProfile { store.finishOriginDrag(token: $0, translation: $1) } },
                    cancel: { store.cancelOriginDrag(token: $0) }, select: {}, toggle: {},
                    precisionKey: { ownsProfile && handlePrecisionKey($0) }, isRectangular: true,
                    clickCancel: { store.endOriginClick(token: $0) },
                    admitsPrimaryPress: { store.admitsCanvasPrimaryPress(clickCount: $0, lease: profileLease) },
                    switchProfile: switchProfile, previewDrag: previewDrag
                )
            }
            .position(x: point.x, y: point.y)
            .allowsHitTesting(enabled)
            .accessibilityLabel("Document origin")
            .accessibilityValue("X \(String(origin.x)), Y \(String(origin.y)), Z \(String(origin.z))")
            .help(
                "Drag the marker to move the origin. Move Origin offers a larger target. Use Document Origin fields for keyboard coordinate editing."
            )
    }
}
