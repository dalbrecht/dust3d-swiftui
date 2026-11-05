import Dust3DDocument
import Dust3DEditorModel
import SwiftUI

/// Keyboard and accessibility equivalent of bending an endpoint on the canvas.
struct EndpointBendControls: View {
    let store: EditorStore
    let endpointID: String

    var body: some View {
        if let snapshot = store.snapshot, let context = store.canvasRotationContext,
            let target = EndpointIKTarget(endpointID: endpointID, snapshot: snapshot)
        {
            DisclosureGroup("Bend Endpoint") {
                EndpointBendFields(store: store, context: context, target: target, locks: snapshot.locks)
                    .id(context)
            }
        }
    }
}

struct EndpointBendFields: View {
    let store: EditorStore
    let context: CanvasRotationContext
    let target: EndpointIKTarget
    let locks: Set<EditingConstraint>
    @State private var horizontal = ""
    @State private var vertical = ""

    private var horizontalAxis: EditingConstraint { context.plane == .front ? .x : .z }

    private var destination: NodePosition? {
        let point = target.endpointPosition
        guard let h = coordinate(horizontal, fallback: horizontalAxis == .x ? point.x : point.z, axis: horizontalAxis),
            let y = coordinate(vertical, fallback: point.y, axis: .y)
        else { return nil }
        return .init(x: horizontalAxis == .x ? h : point.x, y: y, z: horizontalAxis == .z ? h : point.z)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Target \(horizontalAxis.rawValue)", text: $horizontal)
                .accessibilityIdentifier("endpoint-target-horizontal")
                .disabled(locks.contains(horizontalAxis))
            TextField("Target Y", text: $vertical)
                .accessibilityIdentifier("endpoint-target-vertical")
                .disabled(locks.contains(.y))
            Button("Apply Bend", action: submit)
                .disabled(destination == nil || destination == target.endpointPosition)
            if destination == nil {
                Text("Enter coordinates between −1,000,000 and 1,000,000.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Enter a target in the current canvas plane. Blank fields keep the current coordinate.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onSubmit(submit)
        .focusedValue(\.editorTextEditing, true)
        .disabled(store.isWorking || store.isAddingNodes || store.isMovingOrigin || !target.canBend)
    }

    private func coordinate(_ text: String, fallback: Double, axis: EditingConstraint) -> Double? {
        if locks.contains(axis) || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return fallback }
        guard let value = CanvasRotationInput.angle(from: text), abs(value) <= 1_000_000 else { return nil }
        return value
    }

    private func submit() {
        guard let destination, destination != target.endpointPosition else { return }
        store.bendEndpoint(target, toward: destination, context: context)
    }
}
