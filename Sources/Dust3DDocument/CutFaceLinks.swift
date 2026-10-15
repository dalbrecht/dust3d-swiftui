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

    static func index(_ ids: [String]) throws -> [String: String] {
        var result: [String: String] = [:]
        for id in ids {
            guard let canonical = canonicalID(id) else { continue }
            guard result.updateValue(id, forKey: canonical) == nil else { throw DocumentError.invalidNode }
        }
        return result
    }

    static func target(_ value: String?, in parts: [String: String]) -> String? {
        guard let value, let canonical = canonicalID(value) else { return nil }
        return parts[canonical]
    }
}
