import Foundation

/// Upstream sibling-order operations. They never change a component's parent or descendants.
public enum ComponentOrderMove: CaseIterable, Hashable, Sendable {
    case up
    case down
    case first
    case last

    /// Resolve a final sibling index without intermediate-index adjustment.
    /// - Parameters:
    ///   - currentIndex: Zero-based current position.
    ///   - count: Number of siblings, including the selected component.
    /// - Returns: Final index, or nil for invalid input or an already-reached boundary.
    public func destinationIndex(from currentIndex: Int, count: Int) -> Int? {
        guard count > 0, (0..<count).contains(currentIndex) else { return nil }
        let destination: Int
        switch self {
        case .up: destination = max(0, currentIndex - 1)
        case .down: destination = min(count - 1, currentIndex + 1)
        case .first: destination = 0
        case .last: destination = count - 1
        }
        return destination == currentIndex ? nil : destination
    }
}

/// Reorder only known component slots; comments, whitespace and opaque sibling elements retain their slots.
enum ComponentReordering {
    static func apply(_ model: XMLDocument, id: String, direction: ComponentOrderMove) throws -> Bool {
        _ = try ComponentHierarchy.read(model)
        guard
            let element = PartSplitting.componentElements(model).first(where: {
                $0.attribute(forName: "id")?.stringValue == id
            }), let parent = element.parent as? XMLElement
        else { throw DocumentError.missingComponent(id) }
        let siblings = parent.elements(forName: "component")
        guard let index = siblings.firstIndex(where: { $0 === element }) else {
            throw DocumentError.invalidComponent
        }
        guard let destination = direction.destinationIndex(from: index, count: siblings.count) else { return false }
        var reordered = siblings
        reordered.insert(reordered.remove(at: index), at: destination)
        let original = parent.children ?? []
        for child in original { child.detach() }
        var componentIndex = 0
        for child in original {
            if child.kind == .element && child.name == "component" {
                parent.addChild(reordered[componentIndex])
                componentIndex += 1
            } else {
                parent.addChild(child)
            }
        }
        return true
    }
}
