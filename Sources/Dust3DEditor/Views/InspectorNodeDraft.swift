import Dust3DDocument
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

    func reset(_ node: EditableNode) {
        x = node.position.x
        y = node.position.y
        z = node.position.z
        radius = node.radius
        resetID = UUID()
    }
}
