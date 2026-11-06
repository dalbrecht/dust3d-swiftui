import Dust3DEditorModel
import SwiftUI

/// Ambiguous user names need an exact endpoint discriminator before choosing destructive settings ownership.
enum NodeConnectionPresentation {
    static func title(owner: NodeConnectionOwner, choices: [NodeConnectionOwner]) -> String {
        func base(_ value: NodeConnectionOwner) -> String {
            "Keep \(value.partTitle) Settings (\(value.nodeTitle))"
        }
        let title = base(owner)
        return choices.filter { base($0) == title }.count > 1 ? "\(title) [\(owner.nodeID)]" : title
    }
}

/// The inspector and Canvas menu share one captured action and explicit cross-part ownership choice.
struct NodeConnectionControls: View {
    let store: EditorStore?
    var body: some View {
        if let store, let snapshot = store.snapshot {
            let target = NodeConnectionTarget(snapshot: snapshot)
            if target.requiresOwnershipChoice {
                Menu("Connect Selected Nodes") {
                    ForEach(target.owners) { owner in
                        Button(
                            NodeConnectionPresentation.title(owner: owner, choices: target.owners),
                            action: store.nodeConnectionAction(target, ownerID: owner.nodeID)
                        )
                        .disabled(!store.canConnectSelectedNodes(target, ownerID: owner.nodeID))
                    }
                }
                .disabled(!store.canConnectSelectedNodes(target))
                .accessibilityIdentifier("node-connect-selected")
                .help("Choose which part's settings survive the join. One Undo restores both parts.")
            } else {
                Button(
                    "Connect Selected Nodes",
                    action: store.nodeConnectionAction(target, ownerID: target.owners.first?.nodeID ?? "")
                )
                .disabled(!store.canConnectSelectedNodes(target))
                .accessibilityIdentifier("node-connect-selected")
                .help("Connects the two selected endpoints in one Undo step.")
            }
        } else {
            Button("Connect Selected Nodes") {}.disabled(true)
        }
    }
}
