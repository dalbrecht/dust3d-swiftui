import Dust3DDocument

/// A typed color override change; nil removes the explicit component color rather than assigning white.
public struct ComponentColorUpdate: Equatable, Sendable {
    public let componentID: String
    public let color: DocumentColor?

    /// Construct one independently resolved component mutation.
    public init(componentID: String, color: DocumentColor?) {
        self.componentID = componentID
        self.color = color
    }
}

/// Pure graph-selection color planning; applying the commands as one transaction is the actor's responsibility.
public struct GraphReferenceColorPlan: Sendable {
    public let updates: [ComponentColorUpdate]
    public let skippedReadOnlyObjects: Int
    public let skippedOutsideObjects: Int

    /// Document mutations for a single atomic editor transaction; unrelated material/image fields are untouched.
    public var commands: [DocumentCommand] {
        guard !updates.isEmpty else { return [] }
        return [.setComponentColors(updates.map { .init(componentID: $0.componentID, color: $0.color) })]
    }

    /// Qt exposes the Colorize menu only when an explicit node is selected, even for mixed selections.
    public static func canColorize(snapshot: EditorSnapshot) -> Bool { !snapshot.selectedIDs.isEmpty }

    /// Clear each editable part color represented by explicit selected nodes; selected edges contribute nothing.
    /// - Throws: `unresolvableOwner`/`ambiguousOwner` rather than guessing ownership from nearby objects.
    public static func clear(snapshot: EditorSnapshot) throws -> Self {
        let ownership = Ownership(snapshot: snapshot)
        var components = Set<String>()
        var skipped = 0
        for node in snapshot.selectedNodes {
            guard let componentID = try ownership.resolve(partID: node.partID, objectID: node.id) else {
                skipped += 1
                continue
            }
            components.insert(componentID)
        }
        return Self(
            updates: components.sorted().map { .init(componentID: $0, color: nil) }, skippedReadOnlyObjects: skipped,
            skippedOutsideObjects: 0)
    }

    /// Sample explicit node centers and explicit edge midpoints under their actual stored part ownership.
    /// Distinct byte RGB triples have equal weight; duplicate frequencies and alpha do not affect the opaque mean.
    /// - Parameters: `raster` is already fitted; `layout` is frozen from the corresponding displayed reference.
    /// - Throws: Typed ownership errors before any mutation. Read-only objects and outside samples are counted/skipped.
    public static func autoColor(
        snapshot: EditorSnapshot, raster: ReferenceColorRaster, layout: ReferenceColorSamplingLayout
    ) throws -> Self {
        let ownership = Ownership(snapshot: snapshot)
        let nodes = Dictionary(uniqueKeysWithValues: snapshot.nodes.map { ($0.id, $0) })
        var samples: [String: Set<UInt32>] = [:]
        var readOnly = 0
        var outside = 0
        func sample(partID: String?, objectID: String, position: NodePosition) throws {
            guard let componentID = try ownership.resolve(partID: partID, objectID: objectID) else {
                readOnly += 1
                return
            }
            guard let color = layout.color(for: position, in: raster) else {
                outside += 1
                return
            }
            let rgb = UInt32(color.red) << 16 | UInt32(color.green) << 8 | UInt32(color.blue)
            samples[componentID, default: []].insert(rgb)
        }
        for node in snapshot.selectedNodes {
            try sample(partID: node.partID, objectID: node.id, position: node.value.position)
        }
        for edge in snapshot.edges where snapshot.selectedEdgeIDs.contains(edge.id) {
            guard let from = nodes[edge.fromID]?.value.position, let to = nodes[edge.toID]?.value.position else {
                throw ReferenceColorError.unresolvableOwner(edge.id)
            }
            try sample(
                partID: edge.partID, objectID: edge.id,
                position: .init(x: from.x / 2 + to.x / 2, y: from.y / 2 + to.y / 2, z: from.z / 2 + to.z / 2))
        }
        let updates = samples.sorted { $0.key < $1.key }.map { entry -> ComponentColorUpdate in
            let colors = entry.value
            var red: UInt64 = 0
            var green: UInt64 = 0
            var blue: UInt64 = 0
            for color in colors {
                red += UInt64((color >> 16) & 255)
                green += UInt64((color >> 8) & 255)
                blue += UInt64(color & 255)
            }
            // Every entry was created by one real sample; document graph limits bound the distinct count.
            let count = UInt64(colors.count)
            return .init(
                componentID: entry.key,
                color: .init(red: UInt8(red / count), green: UInt8(green / count), blue: UInt8(blue / count)))
        }
        return Self(updates: updates, skippedReadOnlyObjects: readOnly, skippedOutsideObjects: outside)
    }
}

private struct Ownership {
    let parts: [String: DocumentPart]
    let components: [String: [String]]

    init(snapshot: EditorSnapshot) {
        parts = Dictionary(uniqueKeysWithValues: snapshot.parts.map { ($0.id, $0) })
        var components: [String: [String]] = [:]
        for row in snapshot.componentTree.rows {
            if let part = row.component.partID { components[part, default: []].append(row.id) }
        }
        self.components = components
    }

    func resolve(partID: String?, objectID: String) throws -> String? {
        guard let partID, let part = parts[partID] else {
            throw ReferenceColorError.unresolvableOwner(objectID)
        }
        // Inspection can retain a locked/hidden/disabled part without an interpretable component link.
        // It cannot contribute a mutation, so do not require mutable ownership merely to skip it.
        guard part.isEditable else { return nil }
        guard let owners = components[partID], !owners.isEmpty else {
            throw ReferenceColorError.unresolvableOwner(objectID)
        }
        guard owners.count == 1, let componentID = owners.first else {
            throw ReferenceColorError.ambiguousOwner(partID)
        }
        return componentID
    }
}
