import Dust3DDocument
import SwiftUI

/// Document-owned rig intent; this control never starts a skeleton or pose evaluator.
struct RigSettingsControls: View {
    let store: EditorStore
    private let isAssignmentPresented: @MainActor () -> Bool
    @State private var isExpanded: Bool

    init(
        store: EditorStore, isExpanded: Bool = false, isAssignmentPresented: @escaping @MainActor () -> Bool = { true }
    ) {
        self.store = store
        self.isAssignmentPresented = isAssignmentPresented
        _isExpanded = State(initialValue: isExpanded)
    }

    var body: some View {
        let disclosure = $isExpanded
        return DisclosureGroup(isExpanded: disclosure) {
            VStack(alignment: .leading, spacing: 8) {
                if let settings = store.snapshot?.rigSettings {
                    let target = store.rigSettingsTarget
                    Text("Template").font(.caption).foregroundStyle(.secondary)
                    Picker(
                        "Rig template",
                        selection: Binding<DocumentRigType?>(
                            get: { settings.rigType },
                            set: { type in
                                guard let type, let target else { return }
                                store.editRigSettings(.template(type), target: target)
                            }
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
                    .disabled(target == nil)
                    if settings.rigType == nil {
                        Text("Unsupported template retained. Choose a template to replace it.")
                            .font(.caption).foregroundStyle(.primary)
                    }
                    RigTemplateBoneBrowser(store: store, sourceType: settings.sourceRigType) {
                        disclosure.wrappedValue && isAssignmentPresented()
                    }
                    Toggle(
                        "Head bone has eyelids",
                        isOn: Binding(
                            get: { settings.headHasEyelids },
                            set: { enabled in
                                guard let target else { return }
                                store.editRigSettings(.eyelids(enabled), target: target)
                            }
                        )
                    )
                    .frame(minHeight: 40, alignment: .leading)
                    .accessibilityIdentifier("rig-eyelids")
                    .disabled(target == nil)
                } else {
                    Text("Open a document to edit rig settings.").font(.caption)
                }
                #if MOTE3D_EXPERIMENTAL_GENERATED_RIG
                    Text(
                        "Changes are included when you save. Generated rest preview is experimental; pose preview is not available yet."
                    )
                    .font(.caption).foregroundStyle(.primary)
                #else
                    Text(
                        "Changes are included when you save. Skeleton generation and pose preview are not available yet."
                    )
                    .font(.caption).foregroundStyle(.primary)
                #endif
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
