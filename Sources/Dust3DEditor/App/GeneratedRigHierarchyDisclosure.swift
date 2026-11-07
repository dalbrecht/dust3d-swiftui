import Dust3DKit
import Foundation
import Observation

/// Window-owned hierarchy navigation. Source indices belong to one generation;
/// labels, camera state, document data and display work never determine disclosure.
@MainActor @Observable
final class GeneratedRigHierarchyDisclosure {
    struct Reveal: Sendable, Hashable {
        let id: UUID
        let revision: UUID
        let index: Int
    }

    private(set) var revision: UUID?
    private(set) var selectedIndex: Int?
    private(set) var expanded: Set<Int> = []
    private(set) var isExpanded = false
    private(set) var reveal: Reveal?
    @ObservationIgnored private var paths: [Int: [Int]] = [:]
    @ObservationIgnored private var branches: Set<Int> = []

    func sync(hierarchy: GeneratedRigHierarchy?, revision: UUID?, selected: Int?) {
        guard let hierarchy, let revision else {
            self.revision = nil
            selectedIndex = nil
            expanded = []
            isExpanded = false
            reveal = nil
            paths = [:]
            branches = []
            return
        }
        if self.revision != revision {
            self.revision = revision
            selectedIndex = nil
            expanded = []
            isExpanded = false
            reveal = nil
            paths = [:]
            branches = []
            var pending = hierarchy.roots.reversed().map { (node: $0, ancestors: [Int]()) }
            while let frame = pending.popLast() {
                paths[frame.node.index] = frame.ancestors
                if let children = frame.node.children, !children.isEmpty {
                    branches.insert(frame.node.index)
                    let ancestors = frame.ancestors + [frame.node.index]
                    for child in children.reversed() { pending.append((node: child, ancestors: ancestors)) }
                }
            }
        }
        let selection = selected.flatMap { paths[$0] == nil ? nil : $0 }
        guard selectedIndex != selection else { return }
        selectedIndex = selection
        reveal = nil
        if selection != nil { revealSelected(revision: revision) }
    }

    func revealSelected(revision: UUID) {
        guard self.revision == revision, let selectedIndex, let ancestors = paths[selectedIndex] else { return }
        expanded.formUnion(ancestors)
        isExpanded = true
        reveal = Reveal(id: UUID(), revision: revision, index: selectedIndex)
    }

    /// Nil addresses the outer disclosure; only existing branches can expand.
    /// A manual change wins over any queued automatic scroll without changing selection.
    func setExpanded(_ value: Bool, index: Int?, revision: UUID) {
        guard self.revision == revision else { return }
        if let index {
            guard branches.contains(index), expanded.contains(index) != value else { return }
            if value { expanded.insert(index) } else { expanded.remove(index) }
        } else {
            guard isExpanded != value else { return }
            isExpanded = value
        }
        invalidateReveal()
    }

    func invalidateReveal() { reveal = nil }

    func accepts(_ reveal: Reveal) -> Bool {
        guard self.reveal == reveal, revision == reveal.revision, selectedIndex == reveal.index,
            isExpanded, let ancestors = paths[reveal.index]
        else { return false }
        return ancestors.allSatisfy { expanded.contains($0) }
    }
}
