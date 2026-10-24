import Dust3DDocument
import Dust3DEditorModel
import Foundation

/// Stored text intent only; choosing a type or parameter never evaluates native animation.
enum AnimationStoredField {
    case type
    case parameter(String)

    var title: String {
        switch self {
        case .type: return "Stored type"
        case .parameter(let name): return name
        }
    }
    var isEditable: Bool {
        switch self {
        case .type: return true
        case .parameter(let name): return DocumentAnimationParameter.canEditName(name)
        }
    }
    func edit(value: String) -> AnimationEdit {
        switch self {
        case .type: return .setType(value)
        case .parameter(let name): return .setParameter(name: name, value: value)
        }
    }
    var removal: AnimationEdit? {
        switch self {
        case .type: return nil
        case .parameter(let name): return .setParameter(name: name, value: nil)
        }
    }
}

/// One inline draft is bound to the exact document and row seen when Edit was chosen.
struct AnimationValueDraft: Identifiable {
    let id = UUID()
    let target: AnimationEditTarget
    let field: AnimationStoredField
    let originalValue: String
}
