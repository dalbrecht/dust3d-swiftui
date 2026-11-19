import Foundation

/// Structural inspection of controlled test output, not an FBX importer or curve evaluator.
struct FbxAnimationStackInspector {
    struct Stack: Equatable {
        let objectID: Int64
        let titleUTF8: Data
    }

    enum InspectionError: Error { case invalidStructure }

    private let bytes: [UInt8]
    private var nodes = 0
    private var properties = 0
    private var objects = 0
    private var stacks: [Stack] = []
    private static let magic = Array("Kaydara FBX Binary  \0\u{1a}\0".utf8)
    private static let suffix = Array("\0\u{1}AnimStack".utf8)
    private static let maximumBytes = 16 * 1024 * 1024

    static func inspect(_ data: Data) throws -> [Stack] {
        guard (40...maximumBytes).contains(data.count) else { throw InspectionError.invalidStructure }
        var reader = Self(bytes: Array(data))
        guard Array(reader.bytes.prefix(23)) == magic,
            try reader.integer(23, width: 4, limit: reader.bytes.count) == 7400
        else { throw InspectionError.invalidStructure }
        var cursor = 27
        while let end = try reader.node(at: cursor, limit: reader.bytes.count, path: []) { cursor = end }
        guard reader.objects == 1,
            Set(reader.stacks.map(\.objectID)).count == reader.stacks.count
        else { throw InspectionError.invalidStructure }
        // The writer's footer and animation curves are deliberately outside this test contract.
        return reader.stacks
    }

    private func span(_ offset: Int, count: Int, limit: Int) throws -> ArraySlice<UInt8> {
        guard offset >= 0, count >= 0, offset <= limit, limit <= bytes.count, count <= limit - offset
        else { throw InspectionError.invalidStructure }
        return bytes[offset..<offset + count]
    }

    private func integer(_ offset: Int, width: Int, limit: Int) throws -> UInt64 {
        try span(offset, count: width, limit: limit).enumerated().reduce(UInt64(0)) {
            $0 | UInt64($1.element) << (8 * $1.offset)
        }
    }

    private mutating func node(at offset: Int, limit: Int, path: [String]) throws -> Int? {
        let header = try span(offset, count: 13, limit: limit)
        if header.allSatisfy({ $0 == 0 }) { return nil }
        let end = Int(try integer(offset, width: 4, limit: limit))
        let count = Int(try integer(offset + 4, width: 4, limit: limit))
        let propertyBytes = Int(try integer(offset + 8, width: 4, limit: limit))
        let nameBytes = Int(bytes[offset + 12])
        guard end > offset, end <= limit, path.count < 64, nameBytes > 0,
            nodes < 65_536, count <= 4096, count <= 262_144 - properties
        else { throw InspectionError.invalidStructure }
        nodes += 1
        properties += count
        let name = String(decoding: try span(offset + 13, count: nameBytes, limit: end), as: UTF8.self)
        let start = offset + 13 + nameBytes
        _ = try span(start, count: propertyBytes, limit: end)
        let propertyEnd = start + propertyBytes
        let capture = path == ["Objects"] && name == "AnimationStack"
        var cursor = start
        var tags: [UInt8] = []
        var strings: [Data] = []
        var identifier: Int64?
        for _ in 0..<count {
            let tag = try integer(cursor, width: 1, limit: propertyEnd)
            let byteTag = UInt8(tag)
            cursor += 1
            if capture { tags.append(byteTag) }
            switch tag {
            case 89, 67, 73, 70, 68, 76:  // Y C I F D L
                let width = tag == 89 ? 2 : tag == 67 ? 1 : (tag == 68 || tag == 76 ? 8 : 4)
                _ = try span(cursor, count: width, limit: propertyEnd)
                if capture && tag == 76 {
                    identifier = Int64(bitPattern: try integer(cursor, width: 8, limit: propertyEnd))
                }
                cursor += width
            case 83, 82:  // S R
                let size = Int(try integer(cursor, width: 4, limit: propertyEnd))
                cursor += 4
                let value = try span(cursor, count: size, limit: propertyEnd)
                if capture {
                    guard tag == 83, size <= 2048 else { throw InspectionError.invalidStructure }
                    strings.append(Data(value))
                }
                cursor += size
            case 102, 100, 108, 105, 98, 99:  // f d l i b c arrays
                let values = Int(try integer(cursor, width: 4, limit: propertyEnd))
                let encoding = try integer(cursor + 4, width: 4, limit: propertyEnd)
                let size = Int(try integer(cursor + 8, width: 4, limit: propertyEnd))
                let width = tag == 100 || tag == 108 ? 8 : (tag == 98 || tag == 99 ? 1 : 4)
                guard encoding <= 1, values <= Self.maximumBytes / width,
                    encoding != 0 || size == values * width
                else { throw InspectionError.invalidStructure }
                cursor += 12
                _ = try span(cursor, count: size, limit: propertyEnd)
                cursor += size
            default: throw InspectionError.invalidStructure
            }
        }
        guard cursor == propertyEnd else { throw InspectionError.invalidStructure }
        if path.isEmpty && name == "Objects" { objects += 1 }
        if capture {
            guard tags == [76, 83, 83], let identifier, identifier > 0,
                strings.count == 2, strings[1].isEmpty, strings[0].count > Self.suffix.count,
                strings[0].suffix(Self.suffix.count).elementsEqual(Self.suffix)
            else { throw InspectionError.invalidStructure }
            let title = Data(strings[0].dropLast(Self.suffix.count))
            guard !title.contains(0), String(data: title, encoding: .utf8) != nil
            else { throw InspectionError.invalidStructure }
            stacks.append(Stack(objectID: identifier, titleUTF8: title))
        }
        if cursor < end {
            var terminated = false
            while cursor < end {
                if let childEnd = try node(at: cursor, limit: end, path: path + [name]) {
                    cursor = childEnd
                } else {
                    guard end - cursor == 13 else { throw InspectionError.invalidStructure }
                    cursor += 13
                    terminated = true
                    break
                }
            }
            guard terminated else { throw InspectionError.invalidStructure }
        }
        guard cursor == end else { throw InspectionError.invalidStructure }
        return end
    }
}
