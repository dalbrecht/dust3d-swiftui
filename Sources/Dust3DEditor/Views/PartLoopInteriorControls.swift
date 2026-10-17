import Dust3DDocument
import SwiftUI

struct PartLoopInteriorControls: View {
    let store: EditorStore
    let part: DocumentPart

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let value = part.isLoopInteriorFilled {
                Toggle(
                    "Fill isolated loop interior",
                    isOn: Binding(
                        get: { value },
                        set: {
                            store.setPartFillLoopInterior(part.id, value: $0)
                        })
                )
                .accessibilityIdentifier("part-fill-loop-interior")
            } else {
                Text("Fill isolated loop interior").font(.callout)
                Picker(
                    "Fill isolated loop interior",
                    selection: Binding<Bool?>(
                        get: { nil },
                        set: {
                            if let value = $0 { store.setPartFillLoopInterior(part.id, value: value) }
                        })
                ) {
                    Text("Unsupported source value").tag(nil as Bool?).disabled(true)
                    Text("On").tag(Optional(true))
                    Text("Off").tag(Optional(false))
                }
                .labelsHidden().pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Fill isolated loop interior")
                .accessibilityIdentifier("part-fill-loop-interior")
            }
            Text(
                "Applies to closed stitching loops that do not already border a stitched surface. Each change is one undo step."
            )
            .font(.caption).foregroundStyle(.primary)
        }
    }
}
