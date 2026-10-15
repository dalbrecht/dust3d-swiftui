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

    static func target(_ value: String?, in parts: Set<String>) -> String? {
        guard let value, parts.contains(value) else { return nil }
        return value
    }
}
