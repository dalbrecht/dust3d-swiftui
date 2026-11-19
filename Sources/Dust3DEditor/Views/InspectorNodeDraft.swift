import Dust3DDocument
import Dust3DEditorModel
import Foundation
import Observation

/// Per-inspector editing values; Reset also discards a native formatter's unparsed text buffer.
@MainActor @Observable
final class InspectorNodeDraft {
    var x = 0.0
    var y = 0.0
    var z = 0.0
    var radius = 0.0
    private(set) var resetID = UUID()
    private(set) var source: InspectorNodeDraftSource?

    func synchronize(to source: InspectorNodeDraftSource?) {
        guard self.source != source else { return }
        self.source = source
        if let source { reset(source.geometry) }
    }

    func reset(_ node: EditableNode) {
        x = node.position.x
        y = node.position.y
        z = node.position.z
        radius = node.radius
        resetID = UUID()
    }
}

/// Only source identity, selection, and committed geometry reset the numeric fields.
struct InspectorNodeDraftSource: Equatable {
    private let documentIdentity: UUID
    private let selectionRevision: Int
    private let nodeID: Data
    let geometry: EditableNode

    init?(_ snapshot: EditorSnapshot?) {
        guard let snapshot, snapshot.selectedIDs.count == 1, snapshot.selectedEdgeIDs.isEmpty,
            let node = snapshot.selectedNode
        else { return nil }
        documentIdentity = snapshot.documentIdentity
        selectionRevision = snapshot.selectionRevision
        nodeID = Data(node.id.utf8)
        geometry = node.value
    }
}
