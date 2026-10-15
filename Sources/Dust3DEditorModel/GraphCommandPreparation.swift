import Dust3DDocument
import Foundation

/// Session-side preflight allocates UUIDs without introducing randomness into pure state commands.
enum GraphCommandPreparation {
    static func normalizingDeletions(_ commands: [DocumentCommand], document: Dust3DDocument) throws
        -> [DocumentCommand]
    {
        guard
            commands.contains(where: {
                switch $0 {
                case .removeNode, .removeNodes, .removeEdge: true
                default: false
                }
            })
        else { return commands }
        var preview = document
        var affected = Set<String>()
        for command in commands {
            switch command {
            case .removeNode(let id):
                let nodes = try preview.editorContents().nodes
                affected.formUnion(nodes.filter { $0.id == id }.compactMap(\.partID))
            case .removeNodes(let ids):
                let removed = Set(ids)
                let nodes = try preview.editorContents().nodes
                affected.formUnion(nodes.filter { removed.contains($0.id) }.compactMap(\.partID))
            case .removeEdge(let id):
                let contents = try preview.editorContents()
                if let edge = contents.edges.first(where: { $0.id == id }) {
                    affected.formUnion(
                        contents.nodes.filter { $0.id == edge.fromID || $0.id == edge.toID }.compactMap(\.partID))
                }
            default: break
            }
            preview = try preview.applying(command)
        }
        let requirements = try preview.partSplitRequirements(for: affected)
        let splits: [DocumentCommand] = requirements.map { requirement in
            let identities = (0..<requirement.additionalPartCount).map { _ in
                PartSplitIdentity(
                    partID: identifier(), componentIDs: (0..<requirement.componentsPerPart).map { _ in identifier() })
            }
            return .splitPart(id: requirement.partID, identities: identities)
        }
        return commands + splits
    }

    private static func identifier() -> String { "{\(UUID().uuidString.lowercased())}" }
}
