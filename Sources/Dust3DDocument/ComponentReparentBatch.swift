import Foundation

/// A move whose source XML context cannot be represented at the chosen destination.
public enum ComponentReparentError: Error, Equatable, Sendable {
    case inheritedContext(componentID: String, attribute: String)
}

enum ComponentReparentBatch {
    static func apply(_ model: XMLDocument, ids: [String], parentID: String?) throws -> Bool {
        guard ids.count <= ComponentHierarchy.maximumCount else { throw DocumentError.limitExceeded }
        guard !ids.isEmpty else { return false }
        let components = try ComponentHierarchy.read(model)
        let elements = PartSplitting.componentElements(model)
        let indexes = Dictionary(
            uniqueKeysWithValues: components.enumerated().map { (Data($0.element.id.utf8), $0.offset) })
        var selected = Set<Int>()
        for id in ids {
            guard let index = indexes[Data(id.utf8)] else { throw DocumentError.missingComponent(id) }
            selected.insert(index)
        }

        let destination: XMLElement
        let destinationIndex: Int?
        if let parentID {
            guard let index = indexes[Data(parentID.utf8)] else { throw DocumentError.missingComponent(parentID) }
            guard components[index].isGroup else { throw DocumentError.invalidComponentStructure }
            destination = elements[index]
            destinationIndex = index
        } else {
            guard let container = DocumentXML.childElements(model.rootElement(), named: "components").first else {
                throw DocumentError.invalidComponentStructure
            }
            destination = container
            destinationIndex = nil
        }

        var insideSelection = Set<Int>()
        var moves: [(element: XMLElement, id: String)] = []
        for (index, component) in components.enumerated() {
            let parent = component.parentID.flatMap { indexes[Data($0.utf8)] }
            let coveredByParent = parent.map { insideSelection.contains($0) } ?? false
            if coveredByParent || selected.contains(index) {
                insideSelection.insert(index)
                if destinationIndex == index { throw DocumentError.invalidComponentStructure }
                if !coveredByParent && parent != destinationIndex { moves.append((elements[index], component.id)) }
            }
        }
        guard !moves.isEmpty else { return false }
        var contexts = ComponentXMLContexts()
        var budget = DocumentXML.NamespaceBudget()
        for (element, id) in moves {
            try Task.checkCancellation()
            let bindings = try contexts.reparentBindings(element, to: destination, id: id)
            try budget.install(bindings, on: element)
        }
        for (element, _) in moves { element.detach() }
        for (element, _) in moves { destination.addChild(element) }
        try Task.checkCancellation()
        return true
    }
}
