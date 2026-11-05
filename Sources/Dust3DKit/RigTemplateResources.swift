import CryptoKit
import Foundation

/// Resource failures are distinct from native rig generation capability.
public enum RigTemplateResourceError: Error, Equatable, LocalizedError {
    case unsupportedType(String)
    case missingBundle
    case missingResource(String)
    case invalidResource(String)
    case readFailure(String, String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedType(let type): "Unsupported rig template: \(type)"
        case .missingBundle: "The installed rig resource bundle is missing."
        case .missingResource(let name): "Missing rig template resource: \(name)"
        case .invalidResource(let type): "Rig template bytes do not match the pinned source: \(type)"
        case .readFailure(let name, let reason): "Could not read rig template \(name): \(reason)"
        }
    }
}

/// Exact MIT template bytes from pinned core; this API never evaluates a skeleton.
public enum RigTemplateResources {
    public static let maximumBytes = 16384
    public static let sourceRevision = "48b0ce2d6d61cf58731bb0c3e14ef5965a686d68"
    private struct Entry {
        let name: String
        let bytes: Int
        let hash: String
    }
    private static let entries: [String: Entry] = [
        "Biped": Entry(
            name: "rig_biped", bytes: 5818, hash: "eeafc76ba5868aa89f6073374e70d64f0ed994b3608589715739eefaacccfa49"),
        "Quadruped": Entry(
            name: "rig_quadruped", bytes: 3751, hash: "787cfa96921b7fc50ad477b6953dfd5995c8523ad9bcc7b97870cef700747edf"
        ),
        "Bird": Entry(
            name: "rig_bird", bytes: 5023, hash: "137c46e5370f2c95c12d84af0d6cff69250102a2cfe944ab264af1977b8e13ed"),
        "Fish": Entry(
            name: "rig_fish", bytes: 2895, hash: "501cf7d4882cc447ade472a89fdfd58b02b5598ef89a4b47fa438d3a55d91c64"),
        "Snake": Entry(
            name: "rig_snake", bytes: 2278, hash: "d80d22845ea6a5d72e1c13ad36d97b584c24ea1664a3fd7530f7217813d5aff5"),
        "Insect": Entry(
            name: "rig_insect", bytes: 4279, hash: "73f6bb6abb322d1e521153bf7eec3c504979c10032d652c0920248afcc8c608e"),
        "Spider": Entry(
            name: "rig_spider", bytes: 5549, hash: "88a9566a941e609dbbdd7281d144cf3fbfd874e975e357f1c708cf942309ef97"),
    ]

    /// Returns verified owned bytes, or nil for absent/empty/None source intent.
    /// Unknown types and missing, unreadable or altered resources throw explicit errors.
    public static func data(forSourceType type: String?) throws -> Data? {
        try data(forSourceType: type, read: readResource)
    }

    static func data(forSourceType type: String?, read: (String) throws -> Data) throws -> Data? {
        guard let type, !type.isEmpty, type != "None" else { return nil }
        guard let entry = entries[type] else { throw RigTemplateResourceError.unsupportedType(type) }
        let data = try read(entry.name)
        guard data.count <= maximumBytes, data.count == entry.bytes,
            SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == entry.hash
        else { throw RigTemplateResourceError.invalidResource(type) }
        return data
    }

    static func resourceBundle(in process: Bundle) throws -> Bundle {
        guard ["app", "appex"].contains(process.bundleURL.pathExtension.lowercased()) else {
            return Bundle.module
        }
        guard let resources = process.resourceURL,
            let bundle = Bundle(url: resources.appendingPathComponent("Dust3DNative_Dust3DKit.bundle"))
        else { throw RigTemplateResourceError.missingBundle }
        return bundle
    }

    private static func readResource(_ name: String) throws -> Data {
        try readResource(name, in: resourceBundle(in: .main))
    }

    static func readResource(_ name: String, in bundle: Bundle) throws -> Data {
        guard let url = bundle.url(forResource: name, withExtension: "xml", subdirectory: "RigTemplates") else {
            throw RigTemplateResourceError.missingResource(name)
        }
        do {
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            return try file.read(upToCount: maximumBytes + 1) ?? Data()
        } catch {
            throw RigTemplateResourceError.readFailure(name, String(reflecting: error))
        }
    }
}
