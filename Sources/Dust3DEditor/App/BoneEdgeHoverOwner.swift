import Foundation

/// A rendered surface/row owns its hover independently of another row or inspector instance.
struct BoneEdgeHoverOwner: Hashable {
    let surface: UUID
    let row: Data
}
