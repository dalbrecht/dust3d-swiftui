import Dust3DDocument
import SwiftUI

struct PartModifierControls: View {
    let store: EditorStore
    let part: DocumentPart

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shape modifiers").font(.headline)
            ForEach(PartModifierProperty.allCases, id: \.self) { property in
                if let value = part.modifierValue(property) {
                    Toggle(
                        title(property),
                        isOn: Binding(
                            get: { value }, set: { store.setPartModifier(part.id, property: property, value: $0) })
                    )
                    .accessibilityIdentifier("part-modifier-\(property.rawValue)")
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title(property)).font(.callout)
                        Picker(
                            title(property),
                            selection: Binding<Bool?>(
                                get: { nil },
                                set: {
                                    if let value = $0 {
                                        store.setPartModifier(part.id, property: property, value: value)
                                    }
                                })
                        ) {
                            Text("Unsupported source value").tag(nil as Bool?)
                            Text("On").tag(Optional(true))
                            Text("Off").tag(Optional(false))
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(Text(title(property)))
                        .accessibilityIdentifier("part-modifier-\(property.rawValue)")
                    }
                }
            }
            Text(
                "Each change regenerates the mesh in one undo step. Extra rings are on by default; hard joins affect intersections with other parts."
            )
            .font(.caption).foregroundStyle(.primary)
        }
    }

    private func title(_ property: PartModifierProperty) -> String {
        switch property {
        case .subdivision: return "Subdivided cross-section"
        case .chamfer: return "Chamfered cross-section"
        case .roundedEnds: return "Rounded ends"
        case .interpolation: return "Extra rings"
        case .hardJoin: return "Hard joins"
        }
    }
}
