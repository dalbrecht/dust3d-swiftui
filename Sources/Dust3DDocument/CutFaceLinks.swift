import Foundation

/// Match inherited dust3d::Uuid's brace/length/dash classification before interpreting cutFace.
/// Named presets and arbitrary non-UUID part IDs are never profile links.
enum CutFaceLinks {
    static func canonicalID(_ value: String) -> String? {
        let bytes = Array(value.utf8)
        let body: ArraySlice<UInt8>
        if bytes.count == 38, bytes.first == 123 {
            body = bytes.dropFirst().dropLast()
        } else {
            body = bytes[...]
        }
        guard body.count == 36 else { return nil }
        let start = body.startIndex
        guard [8, 13, 18, 23].allSatisfy({ body[start + $0] == 45 }),
            let text = String(bytes: body, encoding: .utf8)
        else { return nil }
        return "{\(text)}"
    }

    /// The generator classifies UUID shape, then looks up the original string verbatim.
    static func index(_ ids: [String]) -> Set<String> {
        Set(ids.filter { canonicalID($0) != nil })
    }

    /// Count saved defaults and owned node overrides using the same link resolution as generation.
    static func referenceCounts(parts: [XMLElement], nodes: [XMLElement]) -> [String: Int] {
        let profiles = Set(
            parts.compactMap { part -> Data? in
                guard PartTargetMetadata.value(part) == .cutFace,
                    let id = part.attribute(forName: "id")?.stringValue, canonicalID(id) != nil
                else { return nil }
                return Data(id.utf8)
            })
        guard !profiles.isEmpty else { return [:] }

        var counts: [String: Int] = [:]
        func count(_ element: XMLElement) {
            if let id = element.attribute(forName: "cutFace")?.stringValue, profiles.contains(Data(id.utf8)) {
                counts[id, default: 0] += 1
            }
        }
        for part in parts { count(part) }
        for node in nodes where node.attribute(forName: "partId") != nil { count(node) }
        return counts
    }

    static func target(_ value: String?, in parts: Set<String>) -> String? {
        guard let value, parts.contains(value) else { return nil }
        return value
    }
}
