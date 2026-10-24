import Dust3DDocument
import SwiftUI

/// Document-owned rig intent; this control never starts a skeleton or pose evaluator.
struct RigSettingsControls: View {
    let store: EditorStore
    @State private var isExpanded: Bool

    init(store: EditorStore, isExpanded: Bool = false) {
        self.store = store
        _isExpanded = State(initialValue: isExpanded)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if let settings = store.snapshot?.rigSettings {
                    Text("Template").font(.caption).foregroundStyle(.secondary)
                    Picker(
                        "Rig template",
                        selection: Binding<DocumentRigType?>(
                            get: { settings.rigType },
                            set: { if let type = $0 { store.setRigType(type) } }
                        )
                    ) {
                        if settings.rigType == nil {
                            Text("Unsupported template").tag(nil as DocumentRigType?).disabled(true)
                        }
                        ForEach(DocumentRigType.allCases, id: \.rawValue) { type in
                            Text(type.rawValue).tag(Optional(type))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .accessibilityLabel("Rig template")
                    .accessibilityIdentifier("rig-template")
                    .disabled(!store.canEditRigSettings)
                    if settings.rigType == nil {
                        Text("Unsupported template retained. Choose a template to replace it.")
                            .font(.caption).foregroundStyle(.primary)
                    }
                    Toggle(
                        "Head bone has eyelids",
                        isOn: Binding(
                            get: { settings.headHasEyelids }, set: { store.setHeadHasEyelids($0) }
                        )
                    )
                    .frame(minHeight: 40, alignment: .leading)
                    .accessibilityIdentifier("rig-eyelids")
                    .disabled(!store.canEditRigSettings)
                } else {
                    Text("Open a document to edit rig settings.").font(.caption)
                }
                Text("Changes are included when you save. Skeleton generation and pose preview are not available yet.")
                    .font(.caption).foregroundStyle(.primary)
            }
        } label: {
            HStack {
                Text("Rig settings").font(.headline)
                Spacer()
                Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(minHeight: 40)
        }
    }

    private var summary: String {
        guard let settings = store.snapshot?.rigSettings else { return "Not loaded" }
        return settings.rigType?.rawValue ?? "Unsupported"
    }
}
