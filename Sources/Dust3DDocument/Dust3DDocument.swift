import Foundation

/// Failures at the archive and editable-node boundary. Invalid commands never change a document.
public enum DocumentError: Error, Equatable, Sendable {
    case invalidArchive
    case invalidXML
    case limitExceeded
    case missingNode(String)
    case invalidNode
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
}

/// Atomic node and graph commands. Unknown archive data remains untouched.
public enum DocumentCommand: Sendable {
    case setNode(id: String, position: NodePosition, radius: Double)
    case addNode(id: String, partID: String, componentID: String?, position: NodePosition, radius: Double)
    case addEdge(id: String, from: String, to: String)
    case removeNode(id: String)
    case removeEdge(id: String)
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

    private func applyingCommand(_ command: DocumentCommand) throws -> Dust3DDocument {
        let contents: DocumentContents
        if case .setNode = command {
            contents = DocumentContents(nodes: [], edges: [])
        } else {
            contents = try editorContents()
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
        case .addNode(let id, let partID, let componentID, let position, let radius):
            guard !id.isEmpty, !partID.isEmpty, !contents.nodes.contains(where: { $0.id == id }),
                contents.nodes.count < 10_000,
                [position.x, position.y, position.z, radius].allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }),
                radius >= 0
            else { throw DocumentError.invalidNode }
            let parts = container("parts")
            if let part = parts.elements(forName: "part").first(where: {
                $0.attribute(forName: "id")?.stringValue == partID
            }) {
                func isTrue(_ value: String?) -> Bool { value == "true" || value == "True" || value == "1" }
                guard !isTrue(part.attribute(forName: "locked")?.stringValue),
                    part.attribute(forName: "visible").map({ isTrue($0.stringValue) }) ?? true
                else { throw DocumentError.invalidNode }
            } else {
                let components = try model.nodes(forXPath: "//component")
                guard components.count < 10_000 else { throw DocumentError.limitExceeded }
                guard let componentID, !componentID.isEmpty,
                    !components.contains(where: {
                        ($0 as? XMLElement)?.attribute(forName: "id")?.stringValue == componentID
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
        case .removeNode(let id):
            _ = try editable(id)
            try Self.findNode(id, in: model).detach()
            for edge in edgeElements()
            where edge.attribute(forName: "from")?.stringValue == id || edge.attribute(forName: "to")?.stringValue == id
            {
                edge.detach()
            }
        case .removeEdge(let id):
            guard let edge = contents.edges.first(where: { $0.id == id }) else { throw DocumentError.invalidNode }
            _ = try editable(edge.fromID)
            _ = try editable(edge.toID)
            edgeElements().first(where: { $0.attribute(forName: "id")?.stringValue == id })?.detach()
        case .setNode(let id, let position, let radius):
            guard [position.x, position.y, position.z, radius].allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }),
                radius >= 0
            else {
                throw DocumentError.invalidNode
            }
            if try node(id: id) == EditableNode(position: position, radius: radius) { return self }
            let node = try Self.findNode(id, in: model)
            for (key, value) in [("x", position.x), ("y", position.y), ("z", position.z), ("radius", radius)] {
                node.attribute(forName: key)?.stringValue = String(value)
            }
            return try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        }
        let next = try replacingModel(model.xmlData(options: [.nodePreserveAll]))
        _ = try next.editorContents()
        return next
    }

    // Commands only replace model XML. Normalize supported numeric spellings and XML
    // serialization when detecting net-zero transactions; retain all unknown data.
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
            for node in try Self.nodes(model) {
                for key in ["x", "y", "z", "radius"] {
                    if let attribute = node.attribute(forName: key),
                        let number = attribute.stringValue.flatMap(Double.init), number.isFinite
                    {
                        attribute.stringValue = String(number == 0 ? 0 : number)
                    }
                }
            }
            return model.xmlData(options: [.nodePreserveAll])
        }
        return try canonical(modelXML) == canonical(other.modelXML)
    }

    private func replacingModel(_ model: Data) throws -> Dust3DDocument {
        guard model.count <= 16 * 1024 * 1024 else { throw DocumentError.limitExceeded }
        let old = items[modelIndex].range
        let delta = model.count - old.count
        let xml = try Self.xml(header, root: "ds3")
        let elements = (xml.rootElement()?.children ?? []).compactMap { $0 as? XMLElement }
        for (index, item) in items.enumerated() {
            if index == modelIndex {
                elements[index].attribute(forName: "size")?.stringValue = String(model.count)
            } else if item.range.lowerBound >= old.upperBound {
                elements[index].attribute(forName: "offset")?.stringValue = String(item.range.lowerBound + delta)
            } else if item.range.isEmpty && old.contains(item.range.lowerBound) {
                // An empty asset has no overlapping bytes, but its anchor must stay in bounds after shrinkage.
                elements[index].attribute(forName: "offset")?.stringValue = String(
                    min(item.range.lowerBound, old.lowerBound + model.count))
            }
        }
        let header = xml.xmlData(options: [.nodePreserveAll])
        // Fixed-width decimal offset makes rebuilding independent of digit growth.
        let start = Data([0xd3, 0x3d]) + Data("DUST3D 1.0 xml ".utf8)
        let offset = start.count + 12 + header.count
        var result = start + Data(String(format: "%010d\r\n", offset).utf8) + header
        var payload = Data(bytes[payloadOffset...])
        payload.replaceSubrange(old, with: model)
        guard result.count <= 256 * 1024 * 1024 - payload.count else { throw DocumentError.limitExceeded }
        result.append(payload)
        return try Dust3DDocument(data: result)
    }

    /// Inspect the editable graph once, retaining source ordering and stable IDs.
    public func editorContents() throws -> DocumentContents {
        let xml = try Self.xml(modelXML, root: "canvas")
        let partContainers = xml.rootElement()?.elements(forName: "parts") ?? []
        let edgeContainers = xml.rootElement()?.elements(forName: "edges") ?? []
        guard partContainers.count <= 1, edgeContainers.count <= 1 else { throw DocumentError.invalidNode }
        var parts: [String: (visible: Bool, editable: Bool)] = [:]
        func isTrue(_ value: String?) -> Bool { value == "true" || value == "True" || value == "1" }
        for part in partContainers.first?.elements(forName: "part") ?? [] {
            guard let id = part.attribute(forName: "id")?.stringValue, parts[id] == nil else {
                throw DocumentError.invalidNode
            }
            let visible = part.attribute(forName: "visible").map { isTrue($0.stringValue) } ?? true
            parts[id] = (visible, visible && !isTrue(part.attribute(forName: "locked")?.stringValue))
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
                value: try Self.decodeNode(node), isVisible: part?.visible ?? true,
                isEditable: part?.editable ?? true)
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
        return DocumentContents(nodes: nodes, edges: edges)
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
