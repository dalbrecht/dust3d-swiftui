import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

struct OriginHandle: View {
    let store: EditorStore
    let origin: NodePosition
    let projection: CanvasProjection

    var body: some View {
        let point = projection.point(for: origin)
        let generation = store.canvasDragGeneration
        ZStack {
            Image(systemName: "scope")
                .font(.title3)
                .foregroundStyle(store.isMovingOrigin ? Color.accentColor : .secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 3, coordinateSpace: .named("node-canvas"))
                        .onChanged { value in
                            store.updateOriginDrag(
                                translation: .init(x: value.translation.width, y: value.translation.height),
                                projection: projection, generation: generation)
                        }
                        .onEnded { value in
                            store.finishOriginDrag(
                                translation: .init(x: value.translation.width, y: value.translation.height),
                                generation: generation)
                        }
                )
                .id(generation)
        }
        .frame(width: 44, height: 44)
        .overlay(alignment: .bottom) {
            Text(store.isMovingOrigin ? "Move Origin · Esc cancels" : "Origin")
                .font(.caption2).fixedSize().offset(y: 8).accessibilityHidden(true)
        }
        .position(x: point.x, y: point.y)
        .allowsHitTesting(store.isMovingOrigin && !store.isWorking)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Document origin")
        .accessibilityValue("X \(String(origin.x)), Y \(String(origin.y)), Z \(String(origin.z))")
        .help("Enable Move Origin to drag. Use Document Origin fields for keyboard coordinate editing.")
    }
}
