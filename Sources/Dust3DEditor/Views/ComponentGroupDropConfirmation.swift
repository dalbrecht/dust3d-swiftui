import SwiftUI

struct ComponentGroupDropConfirmation: View {
    let store: EditorStore

    var body: some View {
        if let proposal = store.pendingComponentGroupDrop {
            VStack(alignment: .leading, spacing: 6) {
                if let source = proposal.sourceTitle {
                    Text("Move “\(source)” into “\(proposal.destinationTitle)”?")
                } else {
                    Text("Move \(proposal.componentCount) selected components into “\(proposal.destinationTitle)”?")
                }
                HStack {
                    Button("Cancel") { store.cancelComponentGroupDrop(proposal.id) }
                    Button("Move") { store.confirmComponentGroupDrop(proposal.id) }
                        .buttonStyle(.borderedProminent)
                }
                .controlSize(.small)
                if let reorder = proposal.siblingReorderTitle {
                    Button(reorder) { store.confirmComponentGroupSiblingReorder(proposal.id) }
                        .controlSize(.small)
                }
            }
            .font(.callout)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 8)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(
                proposal.siblingReorderTitle == nil ? "Confirm move into group" : "Confirm component placement")
        }
    }
}
