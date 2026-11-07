import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

struct OriginHandle: View {
    let store: EditorStore
    let origin: NodePosition
    let projection: CanvasProjection
    var profileLease: UUID? = nil

    private var ownsProfile: Bool { store.ownsCanvasProfile(profileLease) }

    var body: some View {
        let point = projection.point(for: origin)
        let precisionKey = store.canvasPrecisionKeyHandler()
        Image(systemName: "scope")
            .font(.title3)
            .foregroundStyle(store.isMovingOrigin ? Color.accentColor : .secondary)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Text(store.isMovingOrigin ? "Move Origin · Esc cancels" : "Origin")
                    .font(.caption2).fixedSize().offset(y: 8).accessibilityHidden(true)
            }
            .overlay {
                NodePointerSurface(
                    enabled: store.isMovingOrigin && !store.isWorking, canDrag: true,
                    begin: { if ownsProfile { store.beginOriginDrag(token: $0, projection: projection) } },
                    update: { if ownsProfile { store.updateOriginDrag(token: $0, translation: $1) } },
                    finish: { if ownsProfile { store.finishOriginDrag(token: $0, translation: $1) } },
                    cancel: { store.cancelOriginDrag(token: $0) }, select: {}, toggle: {},
                    precisionKey: { ownsProfile && precisionKey($0) }, isRectangular: true,
                    clickCancel: { store.endOriginClick(token: $0) }
                )
            }
            .position(x: point.x, y: point.y)
            .allowsHitTesting(store.isMovingOrigin && !store.isWorking)
            .accessibilityLabel("Document origin")
            .accessibilityValue("X \(String(origin.x)), Y \(String(origin.y)), Z \(String(origin.z))")
            .help("Enable Move Origin to drag. Use Document Origin fields for keyboard coordinate editing.")
    }
}
