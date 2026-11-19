import Dust3DDocument
import Foundation

/// A shape edit belongs to one exact authored Model owner in the captured graph context.
package struct GraphPartShapeTarget: Sendable {
    package static let properties: [PartModifierProperty] = [
        .subdivision, .chamfer, .roundedEnds, .hardJoin, .interpolation,
    ]
    private let context: CanvasAdjustmentTarget
    package let part: DocumentPart?

    package init(snapshot: EditorSnapshot) {
        context = CanvasAdjustmentTarget(snapshot: snapshot)
        if let owners = snapshot.explicitGraphPartKeys(), owners.count == 1, let owner = owners.first {
            part = snapshot.parts.first { $0.target == .model && Data($0.id.utf8) == owner }
        } else {
            part = nil
        }
    }

    package init?(snapshot: EditorSnapshot, canvasTarget: CanvasPartStateTarget) {
        guard canvasTarget.part.target == .model, canvasTarget.isCurrent(in: snapshot) else { return nil }
        context = CanvasAdjustmentTarget(snapshot: snapshot)
        part = canvasTarget.part
    }

    package func isCurrent(in snapshot: EditorSnapshot) -> Bool {
        part != nil && context.isCurrent(in: snapshot)
    }
}

package enum GraphPartShapeError: LocalizedError, Equatable, Sendable {
    case staleTarget, unsupportedModifier

    package var errorDescription: String? {
        switch self {
        case .staleTarget: "The selected part changed. Choose its shape again."
        case .unsupportedModifier: "Choose a supported shape modifier."
        }
    }
}
