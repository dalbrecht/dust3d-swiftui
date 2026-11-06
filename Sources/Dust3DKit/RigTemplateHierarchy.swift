import Foundation

/// A template bone, preserving exact source spelling and sibling order.
public struct RigTemplateBone: Sendable, Identifiable {
    public let name: String
    public let parentName: String
    public let children: [RigTemplateBone]?
    public var id: Data { Data(name.utf8) }
}

/// Invalid template metadata is separate from verified resource-loading failures.
public enum RigTemplateHierarchyError: Error, Equatable, LocalizedError {
    case invalidMetadata(String)
    public var errorDescription: String? {
        switch self {
        case .invalidMetadata(let reason): "Invalid rig template hierarchy: \(reason)"
        }
    }
}

/// Ordered template metadata only. Loading never generates or evaluates a skeleton.
public struct RigTemplateHierarchy: Sendable {
    public let type: String
    public let description: String
    public let bones: [RigTemplateBone]
    public let roots: [RigTemplateBone]

    /// Reads already pinned, hash-verified template bytes. None has no hierarchy;
    /// unsupported types and resource failures retain their original typed errors.
    public static func load(sourceType: String?) throws -> Self? {
        guard let data = try RigTemplateResources.data(forSourceType: sourceType), let sourceType else { return nil }
        return try parse(data, expectedType: sourceType)
    }

    static func parse(_ data: Data, expectedType: String) throws -> Self {
        func invalid(_ reason: String) -> RigTemplateHierarchyError { .invalidMetadata(reason) }
        guard data.count <= RigTemplateResources.maximumBytes,
            let text = String(data: data, encoding: .utf8),
            !text.uppercased().contains("<!DOCTYPE"), !text.uppercased().contains("<!ENTITY")
        else { throw invalid("unsupported size, encoding or entity declaration") }
        let document: XMLDocument
        do { document = try XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever]) } catch {
            throw invalid(String(reflecting: error))
        }
        guard let root = document.rootElement(), root.name == "rig",
            root.attribute(forName: "type")?.stringValue == expectedType
        else { throw invalid("template type does not match") }
        let elements = root.elements(forName: "bone")
        guard !elements.isEmpty, elements.count <= 256 else { throw invalid("invalid bone count") }
        var names: [String] = []
        var parents: [String] = []
        var indices: [Data: Int] = [:]
        for element in elements {
            let name = element.attribute(forName: "name")?.stringValue ?? ""
            let parent = element.attribute(forName: "parent")?.stringValue ?? ""
            guard !name.isEmpty, name.utf8.count <= 1024,
                !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                indices[Data(name.utf8)] == nil
            else { throw invalid("empty, invalid or duplicate bone name") }
            indices[Data(name.utf8)] = names.count
            names.append(name)
            parents.append(parent)
        }
        var children = Array(repeating: [Int](), count: names.count)
        var rootIndices: [Int] = []
        for index in names.indices {
            if !parents[index].isEmpty, let parent = indices[Data(parents[index].utf8)] {
                children[parent].append(index)
            } else {
                // Qt attaches unresolved parents to the invisible tree root.
                rootIndices.append(index)
            }
        }
        // Validate every component, including cycles disconnected from all roots.
        for index in names.indices {
            var visited: Set<Int> = []
            var current: Int? = index
            while let node = current {
                guard visited.insert(node).inserted else { throw invalid("cyclic bone parents") }
                current = parents[node].isEmpty ? nil : indices[Data(parents[node].utf8)]
            }
        }
        func bone(_ index: Int) -> RigTemplateBone {
            RigTemplateBone(
                name: names[index], parentName: parents[index],
                children: children[index].isEmpty ? nil : children[index].map(bone))
        }
        return Self(
            type: expectedType, description: root.elements(forName: "description").first?.stringValue ?? "",
            bones: names.indices.map { RigTemplateBone(name: names[$0], parentName: parents[$0], children: nil) },
            roots: rootIndices.map(bone))
    }
}
