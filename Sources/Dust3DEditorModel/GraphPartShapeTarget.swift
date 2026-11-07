import Dust3DDocument
import Foundation

/// A shape edit belongs to the sole exact authored owner of the explicit graph selection.
package struct GraphPartShapeTarget: Sendable {
    package static let properties: [PartModifierProperty] = [.subdivision, .chamfer, .roundedEnds]
    private let context: CanvasAdjustmentTarget
    package let part: DocumentPart?

    package init(snapshot: EditorSnapshot) {
        context = CanvasAdjustmentTarget(snapshot: snapshot)
        if let owners = snapshot.explicitGraphPartKeys(), owners.count == 1, let owner = owners.first {
            part = snapshot.parts.first { Data($0.id.utf8) == owner }
        } else {
            part = nil
        }
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
        case .unsupportedModifier: "Choose subdivision, chamfer or rounded ends."
        }
    }
}
