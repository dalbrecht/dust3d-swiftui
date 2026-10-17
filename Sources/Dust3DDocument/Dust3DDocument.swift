import Foundation

/// Failures at the archive and editable-node boundary. Invalid commands never change a document.
public enum DocumentError: Error, Equatable, Sendable {
    case invalidArchive
    case invalidXML
    case invalidReferenceImage
    case invalidOrigin
    case limitExceeded
    case missingNode(String)
    case missingPart(String)
    case invalidComponent
    case invalidComponentStructure
    case invalidComponentSmoothing
    case invalidComponentName
    case missingComponent(String)
    case invalidPartName
    case invalidNode
    case cyclicProfile
    case conflictingAsset(String)
    case transactionAlreadyOpen
    case noTransaction
}

public struct NodePosition: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public struct EditableNode: Equatable, Sendable {
    public let position: NodePosition
    public let radius: Double

    public init(position: NodePosition, radius: Double) {
        self.position = position
        self.radius = radius
    }
    /// Geometry values accepted by the document and native-engine boundaries.
    public var isValid: Bool {
        radius >= 0 && [position.x, position.y, position.z, radius].allSatisfy { $0.isFinite && abs($0) <= 1_000_000 }
    }

}

/// One geometry replacement in a bulk update. Identity and unrelated XML stay unchanged.
public struct NodeUpdate: Sendable {
    public let id: String
    public let value: EditableNode
    public init(id: String, value: EditableNode) {
        self.id = id
        self.value = value
    }
}

/// Atomic node and graph commands. Unknown archive data remains untouched.
public enum DocumentCommand: Sendable {
    /// Set finite canvas origin coordinates within ±1,000,000 without moving any nodes.
    case setOrigin(NodePosition)
    /// Rename the legacy part name, preserving component names. Empty input restores the default label.
    case setPartName(id: String, name: String)
    /// Rename one component independently of its linked part; empty input removes its name.
    case setComponentName(id: String, name: String)
    /// Set one component combination mode, clearing legacy component inversion on a semantic change.
    /// Unknown unrelated XML/assets stay intact; semantic no-ops preserve original archive bytes.
    case setComponentCombineMode(id: String, mode: ComponentCombineMode)
    /// Set finite normal smoothing cutoff within 0–180 degrees; zero removes the source attribute.
    /// A semantic no-op retains original spellings/bytes; invalid values throw `invalidComponentSmoothing`.
    case setComponentSmoothCutoffDegrees(id: String, degrees: Double)
    /// Move a component within its current siblings, preserving its entire subtree and all assets.
    case reorderComponent(id: String, direction: ComponentOrderMove)
    /// Wrap nonempty, unique siblings in a fresh unlinked group, retaining their source order.
    case groupComponents(ids: [String], groupID: String)
    /// Remove an unlinked nonempty group and its settings, promoting all child XML at its position.
    case ungroupComponent(id: String)
    /// Append one subtree to an unlinked group or to the document root; cycles reject atomically.
    case reparentComponent(id: String, parentID: String?)
    /// Change a part flag, including restoring a hidden/locked/disabled part.
    case setPartState(id: String, property: PartStateProperty, value: Bool)
    /// Replace Qt's canvas.png asset with PNG-signature bytes (at most 32 MiB), or remove it with nil.
    /// Full raster decoding/validation belongs at the platform import boundary.
    case setReferenceImagePNG(Data?)
    case setNode(id: String, position: NodePosition, radius: Double)
    case setNodes([NodeUpdate])
    case addNode(id: String, partID: String, componentID: String?, position: NodePosition, radius: Double)
    case addEdge(id: String, from: String, to: String)
    case joinNodes(id: String, from: String, to: String)
    case removeNode(id: String)
    case removeNodes([String])
    /// Remove explicitly empty editable parts and their references; retain nested content and all assets.
    case pruneEmptyParts([String])
    case removeEdge(id: String)
    case reverseEdges([String])
    case splitPart(id: String, identities: [PartSplitIdentity])
    case pasteNodes(
        clipboard: NodeClipboard, identities: [String: String], offset: NodePosition,
        partitions: [String: [PartSplitIdentity]] = [:])
}

/// Stable node metadata for editor presentation. Geometry and unknown XML remain in the archive.
public struct DocumentNode: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let partID: String?
    public let value: EditableNode
    public let isVisible: Bool
    public let isEditable: Bool
}

public struct DocumentEdge: Identifiable, Equatable, Sendable {
    public let id: String
    public let fromID: String
    public let toID: String
}

public struct DocumentContents: Sendable {
    public let nodes: [DocumentNode]
    public let edges: [DocumentEdge]
    public let parts: [DocumentPart]
    /// Complete supported stored origin; nil preserves missing/unsupported source fields.
    public let origin: NodePosition?

    init(nodes: [DocumentNode], edges: [DocumentEdge], parts: [DocumentPart] = [], origin: NodePosition? = nil) {
        self.nodes = nodes
        self.edges = edges
        self.parts = parts
        self.origin = origin
    }
}

/// Immutable archive value. Unchanged saves retain every input byte, including unknown assets.
public struct Dust3DDocument: Sendable {
    private struct Item: Sendable {
        let name: String
        let type: String
        let range: Range<Int>
    }

    private let bytes: Data
    private let header: Data
    private let payloadOffset: Int
    private let items: [Item]
    private let modelIndex: Int

    /// Decode a bounded .ds3 archive without generating geometry or interpreting unknown fields.
    /// Throws DocumentError for malformed, ambiguous, external-entity or oversized inputs.
    public init(data: Data) throws {
        guard data.count <= 256 * 1024 * 1024 else { throw DocumentError.limitExceeded }
        let bytes = Data(data)
        guard let lineEnd = bytes.prefix(1024).firstIndex(of: 10) else {
            throw DocumentError.invalidArchive
        }
        var line = Data(bytes[..<lineEnd])
        if line.starts(with: [0xd3, 0x3d]) { line.removeFirst(2) }
        guard let firstLine = String(data: line, encoding: .utf8) else {
            throw DocumentError.invalidArchive
        }
        let tokens = firstLine.split(whereSeparator: { $0.isWhitespace })
        guard tokens.count == 4, tokens[0] == "DUST3D", tokens[1] == "1.0", tokens[2] == "xml",
            let offset = Self.unsigned(String(tokens[3])), offset > lineEnd, offset <= bytes.count,
            offset - lineEnd - 1 <= 1024 * 1024
        else { throw DocumentError.invalidArchive }
        let header = Data(bytes[(lineEnd + 1)..<offset])
        let xml = try Self.xml(header, root: "ds3")
        var items: [Item] = []
        var names = Set<String>()
        for child in xml.rootElement()?.children ?? [] where child.kind == .element {
            guard let element = child as? XMLElement,
                let name = element.attribute(forName: "name")?.stringValue?.trimmingCharacters(
                    in: .whitespacesAndNewlines),
                !name.isEmpty, names.insert(name).inserted,
                let start = Self.unsigned(element.attribute(forName: "offset")?.stringValue),
                let size = Self.unsigned(element.attribute(forName: "size")?.stringValue),
                start <= bytes.count - offset, size <= bytes.count - offset - start,
                let type = element.name
            else { throw DocumentError.invalidArchive }
            items.append(Item(name: name, type: type, range: start..<(start + size)))
        }
        guard items.count <= 10_000 else { throw DocumentError.limitExceeded }
        let ordered = items.sorted { $0.range.lowerBound < $1.range.lowerBound }
        var end = 0
        for item in ordered {
            if item.range.isEmpty { continue }
            guard item.range.lowerBound >= end else { throw DocumentError.invalidArchive }
            end = item.range.upperBound
        }
        let models = items.indices.filter { items[$0].type == "model" }
        guard models.count == 1, let modelIndex = models.first else { throw DocumentError.invalidArchive }
        let range = items[modelIndex].range
        guard range.count <= 16 * 1024 * 1024 else { throw DocumentError.limitExceeded }
        let model = try Self.xml(Data(bytes[(offset + range.lowerBound)..<(offset + range.upperBound)]), root: "canvas")
        var nodeIDs = Set<String>()
        for node in try Self.nodes(model) {
            guard let id = node.attribute(forName: "id")?.stringValue, !id.isEmpty,
                nodeIDs.insert(id).inserted
            else { throw DocumentError.invalidNode }
        }
        self.bytes = bytes
        self.header = header
        self.payloadOffset = offset
        self.items = items
        self.modelIndex = modelIndex
    }

    /// Wrap a Qt canvas snapshot in an asset-free archive using the existing bounded XML validator.
    /// - Parameter snapshotXML: UTF-8 canvas XML, at most 16 MiB; unknown fields are retained verbatim.
    /// - Throws: Typed document errors for malformed XML, excessive depth/size or invalid editable graph data.
    /// - Note: Plain XML cannot carry embedded archive assets. Use the archive initializer for lossless asset transfer.
    /// See the document README for clipboard integration examples.
    public init(snapshotXML: Data) throws {
        guard snapshotXML.count <= 16 * 1024 * 1024 else { throw DocumentError.limitExceeded }
        self = try Dust3DDocument(data: Self.emptyArchive()).replacingModel(Data(snapshotXML))
        _ = try editorContents()
    }

    /// Original or edited model XML; unknown elements and attributes are retained.
    public var modelXML: Data {
        let range = items[modelIndex].range
        return Data(bytes[(payloadOffset + range.lowerBound)..<(payloadOffset + range.upperBound)])
    }

    /// Return archive bytes ready for an atomic file write. No-op saves are byte-identical.
    public func encoded() -> Data { bytes }

    /// Copy an asset by its unique archive name, preserving arbitrary binary content.
    public func asset(named name: String) -> Data? {
        guard let item = items.first(where: { $0.name == name }) else { return nil }
        return Data(bytes[(payloadOffset + item.range.lowerBound)..<(payloadOffset + item.range.upperBound)])
    }

    /// Qt-compatible reference image bytes, if canvas.png is an asset. Opaque input bytes are not decoded here.
    public var referenceImagePNG: Data? {
        guard hasReferenceImage else { return nil }
        return asset(named: "canvas.png")
    }

    /// Inspect the reference-image slot without copying its potentially large payload.
    public var hasReferenceImage: Bool { referenceImageByteCount != nil }

    /// Encoded reference-image length, without materializing its bytes; nil for an absent/non-asset slot.
    public var referenceImageByteCount: Int? {
        items.first { $0.name == "canvas.png" && $0.type == "asset" }?.range.count
    }

    /// Read a complete finite bounded canvas origin, or nil for missing/unsupported coordinates.
    /// Unsupported source attributes remain intact until an explicit origin edit or Undo.
    public func origin() throws -> NodePosition? {
        let model = try Self.xml(modelXML, root: "canvas")
        return model.rootElement().flatMap(Self.decodeOrigin)
    }

    private static func decodeOrigin(_ root: XMLElement) -> NodePosition? {
        let numbers = ["originX", "originY", "originZ"].compactMap {
            root.attribute(forName: $0)?.stringValue.flatMap(Double.init)
        }
        guard numbers.count == 3, numbers.allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }) else { return nil }
        return NodePosition(x: numbers[0], y: numbers[1], z: numbers[2])
    }

    /// Read components in XML preorder without changing the archive.
    /// - Returns: Ordered identities, parent/child links, names and uninterpreted source link attributes.
    /// - Throws: `invalidComponent` for ambiguous identities/containers or unsupported component tags; `limitExceeded` above 10,000 components.
    /// - Example: `try document.components().filter { $0.parentID == nil }` lists root components.
    public func components() throws -> [DocumentComponent] {
        try ComponentHierarchy.read(Self.xml(modelXML, root: "canvas"))
    }

    /// Read supported numeric fields of a node, or throw for a missing/invalid node.
    public func node(id: String) throws -> EditableNode {
        let xml = try Self.xml(modelXML, root: "canvas")
        let node = try Self.findNode(id, in: xml)
        return try Self.decodeNode(node)
    }

    private static func decodeNode(_ node: XMLElement) throws -> EditableNode {
        func number(_ name: String) throws -> Double {
            guard let value = node.attribute(forName: name)?.stringValue.flatMap(Double.init),
                value.isFinite, abs(value) <= 1_000_000
            else { throw DocumentError.invalidNode }
            return value
        }
        let radius = try number("radius")
        guard radius >= 0 else { throw DocumentError.invalidNode }
        return try EditableNode(position: NodePosition(x: number("x"), y: number("y"), z: number("z")), radius: radius)
    }

    /// Apply one validated command to a new document value, preserving all unrelated archive data.
    public func applying(_ command: DocumentCommand) throws -> Dust3DDocument {
        try applyingCommand(command)
    }

    /// Discover bounded identity requirements for splitting only the requested parts.
    public func partSplitRequirements(for partIDs: Set<String>) throws -> [PartSplitRequirement] {
        try PartSplitting.requirements(
            model: Self.xml(modelXML, root: "canvas"), contents: editorContents(), partIDs: partIDs)
    }

    private func applyingCommand(_ command: DocumentCommand) throws -> Dust3DDocument {
        let contents: DocumentContents
        switch command {
        case .setNode, .setNodes, .setReferenceImagePNG, .setOrigin, .setComponentName, .setComponentCombineMode,
            .setComponentSmoothCutoffDegrees,
            .reorderComponent,
            .groupComponents, .ungroupComponent, .reparentComponent:
            contents = DocumentContents(nodes: [], edges: [])
        default: contents = try editorContents()
        }
        let model = try Self.xml(modelXML, root: "canvas")
        guard let root = model.rootElement() else { throw DocumentError.invalidXML }
        func container(_ name: String) -> XMLElement {
            if let existing = root.elements(forName: name).first { return existing }
            let created = XMLElement(name: name)
            root.addChild(created)
            return created
        }
        func element(_ name: String, _ attributes: [(String, String)]) -> XMLElement {
            let result = XMLElement(name: name)
            for (key, value) in attributes {
                let attribute = XMLNode(kind: .attribute)
                attribute.name = key
                attribute.stringValue = value
                result.addAttribute(attribute)
            }
            return result
        }
        func editable(_ id: String) throws -> DocumentNode {
            guard let node = contents.nodes.first(where: { $0.id == id }), node.isEditable else {
                throw DocumentError.invalidNode
            }
            return node
        }
        func edgeElements() -> [XMLElement] { root.elements(forName: "edges").first?.elements(forName: "edge") ?? [] }
        switch command {
        case .setReferenceImagePNG(let png): return try replacingReferenceImage(png)
        case .setOrigin(let position):
            guard [position.x, position.y, position.z].allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }) else {
                throw DocumentError.invalidOrigin
            }
            if Self.decodeOrigin(root) == position { return self }
            for (name, value) in [("originX", position.x), ("originY", position.y), ("originZ", position.z)] {
                let text = String(value == 0 ? 0 : value)
                if let attribute = root.attribute(forName: name) {
                    attribute.stringValue = text
                } else {
                    let attribute = XMLNode(kind: .attribute)
                    attribute.name = name
                    attribute.stringValue = text
                    root.addAttribute(attribute)
                }
            }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .groupComponents(let ids, let groupID):
            try ComponentStructure.group(model, ids: ids, groupID: groupID)
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .ungroupComponent(let id):
            guard try ComponentStructure.ungroup(model, id: id) else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .reparentComponent(let id, let parentID):
            guard try ComponentStructure.reparent(model, id: id, parentID: parentID) else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .reorderComponent(let id, let direction):
            guard try ComponentReordering.apply(model, id: id, direction: direction) else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setComponentSmoothCutoffDegrees(let id, let degrees):
            guard try ComponentSmoothing.set(model, id: id, degrees: degrees) else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setComponentCombineMode(let id, let mode):
            guard try ComponentCombination.set(model, id: id, mode: mode) else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setComponentName(let id, let name):
            guard try ComponentHierarchy.rename(model, id: id, name: name) else { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        case .setPartName(let id, let name):
            guard name.utf8.count <= 1024,
                name.unicodeScalars.allSatisfy({
                    $0.value >= 0x20 && $0.value != 0xFFFE && $0.value != 0xFFFF
                        && !CharacterSet.newlines.contains($0)
                })
            else { throw DocumentError.invalidPartName }
            guard let current = contents.parts.first(where: { $0.id == id }),
                let part = root.elements(forName: "parts").first?.elements(forName: "part").first(where: {
                    $0.attribute(forName: "id")?.stringValue == id
                })
            else { throw DocumentError.missingPart(id) }
            let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if current.name == value { return self }
            part.removeAttribute(forName: "name")
            if !value.isEmpty {
                let attribute = XMLNode(kind: .attribute)
                attribute.name = "name"
                attribute.stringValue = value
                part.addAttribute(attribute)
            }
        case .setPartState(let id, let property, let value):
            guard let current = contents.parts.first(where: { $0.id == id }),
                let part = root.elements(forName: "parts").first?.elements(forName: "part").first(where: {
                    $0.attribute(forName: "id")?.stringValue == id
                })
            else { throw DocumentError.missingPart(id) }
            let previous: Bool
            switch property {
            case .visible: previous = current.isVisible
            case .locked: previous = current.isLocked
            case .disabled: previous = current.isDisabled
            }
            if previous == value { return self }
            part.removeAttribute(forName: property.rawValue)
            let attribute = XMLNode(kind: .attribute)
            attribute.name = property.rawValue
            attribute.stringValue = value ? "true" : "false"
            part.addAttribute(attribute)
        case .addNode(let id, let partID, let componentID, let position, let radius):
            guard !id.isEmpty, !partID.isEmpty, !contents.nodes.contains(where: { $0.id == id }),
                contents.nodes.count < 10_000,
                EditableNode(position: position, radius: radius).isValid
            else { throw DocumentError.invalidNode }
            let parts = container("parts")
            if let part = parts.elements(forName: "part").first(where: {
                $0.attribute(forName: "id")?.stringValue == partID
            }) {
                func isTrue(_ value: String?) -> Bool { value == "true" || value == "True" || value == "1" }
                guard !isTrue(part.attribute(forName: "locked")?.stringValue),
                    !isTrue(part.attribute(forName: "disabled")?.stringValue),
                    part.attribute(forName: "visible").map({ isTrue($0.stringValue) }) ?? true
                else { throw DocumentError.invalidNode }
            } else {
                let components = PartSplitting.componentElements(model)
                guard components.count < 10_000 else { throw DocumentError.limitExceeded }
                guard let componentID, !componentID.isEmpty,
                    !components.contains(where: {
                        $0.attribute(forName: "id")?.stringValue == componentID
                    })
                else { throw DocumentError.invalidNode }
                parts.addChild(
                    element("part", [("id", partID), ("name", "Part"), ("visible", "true"), ("locked", "false")]))
                container("components").addChild(
                    element(
                        "component",
                        [
                            ("id", componentID), ("name", "Part"), ("linkData", partID), ("linkDataType", "partId"),
                            ("combineMode", "Normal"),
                        ]))
            }
            container("nodes").addChild(
                element(
                    "node",
                    [
                        ("id", id), ("partId", partID), ("x", String(position.x)), ("y", String(position.y)),
                        ("z", String(position.z)), ("radius", String(radius)),
                    ]))
        case .addEdge(let id, let from, let to):
            let source = try editable(from)
            let target = try editable(to)
            guard !id.isEmpty, from != to, let partID = source.partID, target.partID == partID,
                contents.edges.count < 20_000,
                !contents.edges.contains(where: {
                    $0.id == id || ($0.fromID == from && $0.toID == to) || ($0.fromID == to && $0.toID == from)
                })
            else { throw DocumentError.invalidNode }
            container("edges").addChild(element("edge", [("id", id), ("partId", partID), ("from", from), ("to", to)]))
        case .joinNodes(let id, let from, let to):
            try PartJoining.apply(id: id, from: from, to: to, model: model, contents: contents)
        case .removeNode(let id):
            return try applying(.removeNodes([id]))
        case .removeNodes(let ids):
            if ids.isEmpty { return self }
            let removed = Set(ids)
            let nodes = Dictionary(uniqueKeysWithValues: contents.nodes.map { ($0.id, $0) })
            guard removed.count == ids.count, ids.allSatisfy({ nodes[$0]?.isEditable == true }) else {
                throw DocumentError.invalidNode
            }
            for node in try Self.nodes(model) where removed.contains(node.attribute(forName: "id")?.stringValue ?? "") {
                node.detach()
            }
            for edge in edgeElements()
            where removed.contains(edge.attribute(forName: "from")?.stringValue ?? "")
                || removed.contains(edge.attribute(forName: "to")?.stringValue ?? "")
            {
                edge.detach()
            }
        case .pruneEmptyParts(let ids):
            if ids.isEmpty { return self }
            try EmptyPartCleanup.apply(ids, model: model, contents: contents)
        case .removeEdge(let id):
            guard let edge = contents.edges.first(where: { $0.id == id }) else { throw DocumentError.invalidNode }
            _ = try editable(edge.fromID)
            _ = try editable(edge.toID)
            edgeElements().first(where: { $0.attribute(forName: "id")?.stringValue == id })?.detach()
        case .reverseEdges(let ids):
            if ids.isEmpty { return self }
            let edges = Dictionary(uniqueKeysWithValues: contents.edges.map { ($0.id, $0) })
            let editable = Set(contents.nodes.filter(\.isEditable).map(\.id))
            guard Set(ids).count == ids.count,
                ids.allSatisfy({ id in
                    guard let edge = edges[id] else { return false }
                    return editable.contains(edge.fromID) && editable.contains(edge.toID)
                })
            else { throw DocumentError.invalidNode }
            let selected = Set(ids)
            for edge in edgeElements() where selected.contains(edge.attribute(forName: "id")?.stringValue ?? "") {
                let from = edge.attribute(forName: "from")?.stringValue
                let to = edge.attribute(forName: "to")?.stringValue
                edge.attribute(forName: "from")?.stringValue = to
                edge.attribute(forName: "to")?.stringValue = from
            }
        case .pasteNodes(let clipboard, let identities, let offset, let partitions):
            try NodeClipboardMutation.paste(
                clipboard, identities: identities, offset: offset, into: model, contents: contents)
            var result = try replacingModel(model.xmlData(options: [.nodePreserveAll])).mergingAssets(
                from: clipboard.document)
            let contents = try result.editorContents()
            let pastedParts = Set(
                try clipboard.document.editorContents().nodes.compactMap(\.partID).compactMap { identities[$0] })
            guard Set(partitions.keys).isSubset(of: pastedParts) else { throw DocumentError.invalidNode }
            let identityCount = partitions.values.reduce(0) { total, plans in
                total + plans.reduce(0) { $0 + 1 + $1.componentIDs.count }
            }
            guard identityCount <= 20_000 else { throw DocumentError.limitExceeded }
            let fresh = partitions.values.flatMap { $0 }.flatMap { [$0.partID] + $0.componentIDs }
            let keys = fresh.map { CutFaceLinks.canonicalID($0) ?? $0 }
            let existing = Set(
                NodeClipboardMutation.semanticElements(model).compactMap { $0.attribute(forName: "id")?.stringValue }
                    .map { CutFaceLinks.canonicalID($0) ?? $0 })
            guard Set(keys).count == keys.count, existing.isDisjoint(with: keys) else {
                throw DocumentError.invalidNode
            }
            for id in partitions.keys.sorted() {
                _ = try PartSplitting.apply(
                    id: id, identities: partitions[id] ?? [], model: model, contents: contents, allowReadOnly: true)
            }
            if !partitions.isEmpty { result = try result.replacingModel(model.xmlData(options: [.nodePreserveAll])) }
            _ = try result.editorContents()
            return result
        case .splitPart(let id, let identities):
            if try !PartSplitting.apply(id: id, identities: identities, model: model, contents: contents) {
                return self
            }
        case .setNode(let id, let position, let radius):
            return try applying(.setNodes([.init(id: id, value: .init(position: position, radius: radius))]))
        case .setNodes(let updates):
            guard Set(updates.map(\.id)).count == updates.count else { throw DocumentError.invalidNode }
            let elements = Dictionary(
                uniqueKeysWithValues: try Self.nodes(model).map {
                    ($0.attribute(forName: "id")?.stringValue ?? "", $0)
                })
            var changed = false
            for update in updates {
                guard update.value.isValid else { throw DocumentError.invalidNode }
                guard let node = elements[update.id] else { throw DocumentError.missingNode(update.id) }
                if try Self.decodeNode(node) == update.value { continue }
                changed = true
                let position = update.value.position
                for (key, value) in [
                    ("x", position.x), ("y", position.y), ("z", position.z), ("radius", update.value.radius),
                ] {
                    node.attribute(forName: key)?.stringValue = String(value)
                }
            }
            if !changed { return self }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        }
        let next = try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        _ = try next.editorContents()
        return next
    }

    // Normalize known serialization differences for net-zero transactions, while comparing every asset and header field.
    func hasSameContents(as other: Dust3DDocument) throws -> Bool {
        func canonicalHeader(_ data: Data) throws -> Data {
            let header = try Self.xml(data, root: "ds3")
            header.isStandalone = false
            for child in header.rootElement()?.children ?? [] {
                guard let element = child as? XMLElement else { continue }
                element.removeAttribute(forName: "offset")
                element.removeAttribute(forName: "size")
            }
            return header.xmlData(options: [.nodePreserveAll])
        }
        guard items.count == other.items.count,
            try canonicalHeader(header) == canonicalHeader(other.header)
        else { return false }
        for (index, item) in items.enumerated() where index != modelIndex {
            let counterpart = other.items[index]
            guard
                bytes[(payloadOffset + item.range.lowerBound)..<(payloadOffset + item.range.upperBound)]
                    == other.bytes[
                        (other.payloadOffset + counterpart.range.lowerBound)..<(other.payloadOffset
                            + counterpart.range.upperBound)]
            else { return false }
        }
        return try hasSameModel(as: other)
    }

    /// Model-only transactions cannot alter assets; avoid traversing opaque payloads on interactive graph edits.
    func hasSameModel(as other: Dust3DDocument) throws -> Bool {
        func canonical(_ data: Data) throws -> Data {
            let model = try Self.xml(data, root: "canvas")
            model.isStandalone = false
            // Absent graph containers and empty containers represent the same graph.
            // Attributes, namespaces, comments and non-whitespace content are metadata.
            for name in ["nodes", "edges"] {
                for container in model.rootElement()?.elements(forName: name) ?? [] {
                    if container.attributes?.isEmpty ?? true, container.namespaces?.isEmpty ?? true,
                        (container.children ?? []).allSatisfy({
                            $0.kind == .text
                                && $0.xmlString(options: [.nodePreserveAll]).trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                ).isEmpty
                        })
                    {
                        container.detach()
                    }
                }
            }
            for key in ["originX", "originY", "originZ"] {
                if let attribute = model.rootElement()?.attribute(forName: key),
                    let number = attribute.stringValue.flatMap(Double.init), number.isFinite, abs(number) <= 1_000_000
                {
                    attribute.stringValue = String(number == 0 ? 0 : number)
                }
            }
            for node in try Self.nodes(model) {
                for key in ["x", "y", "z", "radius"] {
                    if let attribute = node.attribute(forName: key),
                        let number = attribute.stringValue.flatMap(Double.init), number.isFinite
                    {
                        attribute.stringValue = String(number == 0 ? 0 : number)
                    }
                }
            }
            for part in model.rootElement()?.elements(forName: "parts").first?.elements(forName: "part") ?? [] {
                for property in PartStateProperty.allCases {
                    guard let attribute = part.attribute(forName: property.rawValue) else { continue }
                    let value = ["true", "True", "1"].contains(attribute.stringValue ?? "")
                    let defaultValue = property == .visible
                    if value == defaultValue {
                        part.removeAttribute(forName: property.rawValue)
                    } else {
                        attribute.stringValue = value ? "true" : "false"
                    }
                }
            }
            return model.xmlData(options: [.nodePreserveAll])
        }
        return try canonical(modelXML) == canonical(other.modelXML)
    }

    private func replacingModel(_ model: Data) throws -> Dust3DDocument {
        guard model.count <= 16 * 1024 * 1024 else { throw DocumentError.limitExceeded }
        return try replacingItem(at: modelIndex, with: model)
    }

    private func replacingReferenceImage(_ png: Data?) throws -> Dust3DDocument {
        if let png {
            guard png.count <= 32 * 1024 * 1024 else { throw DocumentError.limitExceeded }
            guard png.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) else {
                throw DocumentError.invalidReferenceImage
            }
        }
        if let index = items.firstIndex(where: { $0.name == "canvas.png" }) {
            guard items[index].type == "asset" else { throw DocumentError.conflictingAsset("canvas.png") }
            if png == referenceImagePNG { return self }
            return try replacingItem(at: index, with: png)
        }
        guard let png else { return self }
        guard items.count < 10_000, bytes.count - payloadOffset <= 256 * 1024 * 1024 - png.count else {
            throw DocumentError.limitExceeded
        }
        let xml = try Self.xml(header, root: "ds3")
        let asset = XMLElement(name: "asset")
        for (name, value) in [
            ("name", "canvas.png"), ("offset", String(bytes.count - payloadOffset)), ("size", String(png.count)),
        ] {
            let attribute = XMLNode(kind: .attribute)
            attribute.name = name
            attribute.stringValue = value
            asset.addAttribute(attribute)
        }
        xml.rootElement()?.addChild(asset)
        var payload = Data(bytes[payloadOffset...])
        payload.append(png)
        return try rebuildingArchive(xml, payload: payload)
    }

    /// Replace or remove one item, preserving all unrelated payload bytes, including gaps and trailing data.
    private func replacingItem(at itemIndex: Int, with replacement: Data?) throws -> Dust3DDocument {
        let old = items[itemIndex].range
        let data = replacement ?? Data()
        let nextPayloadCount = bytes.count - payloadOffset - old.count + data.count
        guard nextPayloadCount <= 256 * 1024 * 1024 else { throw DocumentError.limitExceeded }
        let delta = data.count - old.count
        let xml = try Self.xml(header, root: "ds3")
        let elements = (xml.rootElement()?.children ?? []).compactMap { $0 as? XMLElement }
        for (index, item) in items.enumerated() {
            if index == itemIndex {
                if replacement != nil {
                    elements[index].attribute(forName: "size")?.stringValue = String(data.count)
                } else {
                    elements[index].detach()
                }
            } else if item.range.lowerBound >= old.upperBound {
                elements[index].attribute(forName: "offset")?.stringValue = String(item.range.lowerBound + delta)
            } else if item.range.isEmpty && old.contains(item.range.lowerBound) {
                // Empty items have no overlapping bytes, but their anchors must remain in bounds after shrinkage.
                elements[index].attribute(forName: "offset")?.stringValue = String(
                    min(item.range.lowerBound, old.lowerBound + data.count))
            }
        }
        var payload = Data(bytes[payloadOffset...])
        payload.replaceSubrange(old, with: data)
        return try rebuildingArchive(xml, payload: payload)
    }

    private func rebuildingArchive(_ xml: XMLDocument, payload: Data) throws -> Dust3DDocument {
        let header = xml.xmlData(options: [.nodePreserveAll])
        guard header.count <= 1024 * 1024 else { throw DocumentError.limitExceeded }
        let start = Data([0xD3, 0x3D]) + Data("DUST3D 1.0 xml ".utf8)
        let offset = start.count + 12 + header.count
        guard offset <= 256 * 1024 * 1024 - payload.count else { throw DocumentError.limitExceeded }
        return try Dust3DDocument(data: start + Data(String(format: "%010d\r\n", offset).utf8) + header + payload)
    }

    /// Copy selected graph objects and their linked-profile dependencies into a bounded fragment.
    /// Unknown attached fields and all archive assets are retained; canvas-global objects are excluded.
    public func copyingNodes(_ ids: Set<String>) throws -> NodeClipboard {
        let model = try Self.xml(modelXML, root: "canvas")
        try NodeClipboardMutation.extract(ids, model: model, contents: editorContents())
        return try NodeClipboard(
            document: replacingModel(model.xmlData(options: [.nodePreserveAll])), selectedNodeIDs: ids)
    }

    private func mergingAssets(from source: Dust3DDocument) throws -> Dust3DDocument {
        let xml = try Self.xml(header, root: "ds3")
        let sourceXML = try Self.xml(source.header, root: "ds3")
        let destinationElements = (xml.rootElement()?.children ?? []).compactMap { $0 as? XMLElement }
        let sourceElements = (sourceXML.rootElement()?.children ?? []).compactMap { $0 as? XMLElement }
        let existingByName = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.name, $0.offset) })
        var payload = Data(bytes[payloadOffset...])
        var changed = false
        for (index, item) in source.items.enumerated() where index != source.modelIndex {
            if let existingIndex = existingByName[item.name] {
                let existing = items[existingIndex]
                func metadata(_ element: XMLElement) -> String {
                    NodeClipboardMutation.preserveNamespaces(element)
                    let copy = element.copy() as? XMLElement
                    copy?.removeAttribute(forName: "offset")
                    return copy?.xmlString(options: [.nodePreserveAll]) ?? ""
                }
                guard existingIndex != modelIndex, existing.type == item.type,
                    bytes[(payloadOffset + existing.range.lowerBound)..<(payloadOffset + existing.range.upperBound)]
                        == source.bytes[
                            (source.payloadOffset + item.range.lowerBound)..<(source.payloadOffset
                                + item.range.upperBound)],
                    metadata(destinationElements[existingIndex]) == metadata(sourceElements[index])
                else { throw DocumentError.conflictingAsset(item.name) }
                continue
            }
            NodeClipboardMutation.preserveNamespaces(sourceElements[index])
            guard payload.count <= 256 * 1024 * 1024 - item.range.count,
                let copy = sourceElements[index].copy() as? XMLElement
            else { throw DocumentError.limitExceeded }
            copy.attribute(forName: "offset")?.stringValue = String(payload.count)
            xml.rootElement()?.addChild(copy)
            payload.append(
                source.bytes[
                    (source.payloadOffset + item.range.lowerBound)..<(source.payloadOffset + item.range.upperBound)])
            changed = true
        }
        guard changed else { return self }
        let header = xml.xmlData(options: [.nodePreserveAll])
        let start = Data([0xd3, 0x3d]) + Data("DUST3D 1.0 xml ".utf8)
        let offset = start.count + 12 + header.count
        guard offset <= 256 * 1024 * 1024 - payload.count else { throw DocumentError.limitExceeded }
        return try Dust3DDocument(data: start + Data(String(format: "%010d\r\n", offset).utf8) + header + payload)
    }

    /// Inspect the editable graph once, retaining source ordering and stable IDs.
    public func editorContents() throws -> DocumentContents {
        let xml = try Self.xml(modelXML, root: "canvas")
        let partContainers = xml.rootElement()?.elements(forName: "parts") ?? []
        let edgeContainers = xml.rootElement()?.elements(forName: "edges") ?? []
        guard partContainers.count <= 1, edgeContainers.count <= 1 else { throw DocumentError.invalidNode }
        var parts: [String: DocumentPart] = [:]
        var orderedParts: [DocumentPart] = []
        func isTrue(_ value: String?) -> Bool { value == "true" || value == "True" || value == "1" }
        let partElements = partContainers.first?.elements(forName: "part") ?? []
        guard partElements.count <= 10_000 else { throw DocumentError.limitExceeded }
        for (index, part) in partElements.enumerated() {
            guard let id = part.attribute(forName: "id")?.stringValue, !id.isEmpty, parts[id] == nil else {
                throw DocumentError.invalidNode
            }
            let visible = part.attribute(forName: "visible").map { isTrue($0.stringValue) } ?? true
            let value = DocumentPart(
                id: id, name: part.attribute(forName: "name")?.stringValue ?? "", index: index,
                isVisible: visible, isLocked: isTrue(part.attribute(forName: "locked")?.stringValue),
                isDisabled: isTrue(part.attribute(forName: "disabled")?.stringValue))
            parts[id] = value
            orderedParts.append(value)
        }
        let elements = try Self.nodes(xml)
        guard elements.count <= 10_000 else { throw DocumentError.limitExceeded }
        let nodes = try elements.enumerated().map { index, node -> DocumentNode in
            guard let id = node.attribute(forName: "id")?.stringValue else { throw DocumentError.invalidNode }
            let partID = node.attribute(forName: "partId")?.stringValue
            if let partID, parts[partID] == nil { throw DocumentError.invalidNode }
            let part = partID.flatMap { parts[$0] }
            let name = node.attribute(forName: "name")?.stringValue ?? ""
            return DocumentNode(
                id: id, title: name.isEmpty ? "Node \(index + 1)" : name, partID: partID,
                value: try Self.decodeNode(node), isVisible: part?.isEditVisible ?? true,
                isEditable: part?.isEditable ?? true)
        }
        let ids = Set(nodes.map(\.id))
        var edgeIDs = Set<String>()
        let edges = try (edgeContainers.first?.elements(forName: "edge") ?? []).map { edge -> DocumentEdge in
            guard let id = edge.attribute(forName: "id")?.stringValue, edgeIDs.insert(id).inserted,
                let from = edge.attribute(forName: "from")?.stringValue,
                let to = edge.attribute(forName: "to")?.stringValue,
                ids.contains(from), ids.contains(to)
            else { throw DocumentError.invalidNode }
            return DocumentEdge(id: id, fromID: from, toID: to)
        }
        guard edges.count <= 20_000 else { throw DocumentError.limitExceeded }
        return DocumentContents(
            nodes: nodes, edges: edges, parts: orderedParts, origin: xml.rootElement().flatMap(Self.decodeOrigin))
    }

    /// Construct a valid blank document for a native untitled document window.
    public static func emptyArchive() -> Data {
        let model = Data(
            "<canvas originX='0.5' originY='0.5' originZ='0.5'><nodes/><edges/><parts/><components/></canvas>".utf8)
        let header = "<ds3><model name='model.xml' offset='0' size='\(model.count)'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
            + model
    }

    private static func unsigned(_ text: String?) -> Int? {
        guard let text, !text.isEmpty, text.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
        return Int(text)
    }

    private static func nodes(_ xml: XMLDocument) throws -> [XMLElement] {
        let containers = xml.rootElement()?.elements(forName: "nodes") ?? []
        guard containers.count <= 1 else { throw DocumentError.invalidNode }
        return containers.first?.elements(forName: "node") ?? []
    }

    private static func findNode(_ id: String, in xml: XMLDocument) throws -> XMLElement {
        guard let node = try nodes(xml).first(where: { $0.attribute(forName: "id")?.stringValue == id }) else {
            throw DocumentError.missingNode(id)
        }
        return node
    }

    private static func xml(_ data: Data, root: String) throws -> XMLDocument {
        guard let text = String(data: data, encoding: .utf8), !text.contains("\0"),
            !text.uppercased().contains("<!DOCTYPE"), !text.uppercased().contains("<!ENTITY")
        else { throw DocumentError.invalidXML }
        let delegate = XMLDepthValidator()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), !delegate.exceeded else { throw DocumentError.invalidXML }
        do {
            let document = try XMLDocument(data: data, options: [.nodePreserveAll, .nodeLoadExternalEntitiesNever])
            guard document.rootElement()?.name == root else { throw DocumentError.invalidXML }
            return document
        } catch { throw DocumentError.invalidXML }
    }
}

private final class XMLDepthValidator: NSObject, XMLParserDelegate {
    private var depth = 0
    private var count = 0
    var exceeded = false

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
        attributes: [String: String]
    ) {
        depth += 1
        count += 1
        if depth > 128 || count > 100_000 {
            exceeded = true
            parser.abortParsing()
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        depth -= 1
    }
}
