import Foundation

/// Typed admission failures for private recovery copies, independent of filesystem operations.
public enum RecoveryCopyPlanError: Error, Sendable, Equatable {
    case tooManyDocuments, tooManyFiles, invalidRequest, invalidInventory, storageLimitExceeded
}

/// Metadata for an accepted document snapshot; the writer supplies its actual encoded byte count.
public struct RecoveryCopyRequest: Sendable, Equatable {
    public let documentID: UUID
    public let revision: Int
    public let byteCount: Int
    /// A stable app-owned basename; callers cannot supply or redirect a destination path.
    public var filename: String { documentID.uuidString.lowercased() + ".ds3" }

    /// Describe a snapshot without copying or allocating its payload.
    /// - Parameters: documentID identifies an open document; revision is its accepted epoch; byteCount is encoded size.
    /// - Note: RecoveryCopyPlan validates these values before any write.
    public init(documentID: UUID, revision: Int, byteCount: Int) {
        self.documentID = documentID
        self.revision = revision
        self.byteCount = byteCount
    }
}

/// Bounded retained-file metadata supplied by the private-directory adapter.
public struct RecoveryCopyInventoryEntry: Sendable {
    public let name: String
    public let byteCount: Int

    /// Describe one regular file without opening its payload. Validation occurs during planning.
    public init(name: String, byteCount: Int) {
        self.name = name
        self.byteCount = byteCount
    }
}

/// Pure retained-byte admission. It neither changes document history nor reads/writes files.
public struct RecoveryCopyPlan: Sendable {
    public static let maximumRetainedBytes = 256 * 1024 * 1024
    public static let maximumDocuments = 16
    public static let maximumFiles = 4096
    /// Shrinking replacements precede growth, so retained files stay inside the admitted budget.
    public let requests: [RecoveryCopyRequest]
    public let retainedByteCount: Int

    /// Admit a batch against existing regular files with checked integer arithmetic.
    /// - Parameters: requests are distinct accepted snapshots; inventory is retained file metadata; maximumBytes may lower the production cap.
    /// - Throws: RecoveryCopyPlanError for invalid metadata, excessive count or retained bytes.
    /// - Note: Atomic staging may temporarily require one additional snapshot's disk space. This is not an OS quota.
    /// - Example: `let plan = try RecoveryCopyPlan(requests: snapshots, inventory: files)`.
    public init(
        requests: [RecoveryCopyRequest], inventory: [RecoveryCopyInventoryEntry],
        maximumBytes: Int = maximumRetainedBytes
    ) throws {
        guard requests.count <= Self.maximumDocuments else { throw RecoveryCopyPlanError.tooManyDocuments }
        guard inventory.count <= Self.maximumFiles else { throw RecoveryCopyPlanError.tooManyFiles }
        guard maximumBytes > 0, maximumBytes <= Self.maximumRetainedBytes else {
            throw RecoveryCopyPlanError.invalidInventory
        }
        var sizes: [String: Int] = [:]
        var retained = 0
        for entry in inventory {
            guard !entry.name.isEmpty, entry.name != ".", entry.name != "..", !entry.name.contains("/"),
                !entry.name.contains("\0"), entry.name.utf8.count <= 1024,
                entry.byteCount >= 0, sizes[entry.name] == nil
            else { throw RecoveryCopyPlanError.invalidInventory }
            guard entry.byteCount <= maximumBytes - retained else { throw RecoveryCopyPlanError.storageLimitExceeded }
            sizes[entry.name] = entry.byteCount
            retained += entry.byteCount
        }
        var identifiers: Set<UUID> = []
        var newFiles = 0
        for request in requests {
            guard request.revision >= 0, request.byteCount > 0, identifiers.insert(request.documentID).inserted else {
                throw RecoveryCopyPlanError.invalidRequest
            }
            guard request.byteCount <= maximumBytes else { throw RecoveryCopyPlanError.storageLimitExceeded }
            if sizes[request.filename] == nil { newFiles += 1 }
            retained -= sizes[request.filename] ?? 0
        }
        guard newFiles <= Self.maximumFiles - inventory.count else { throw RecoveryCopyPlanError.tooManyFiles }
        for request in requests {
            guard request.byteCount <= maximumBytes - retained else { throw RecoveryCopyPlanError.storageLimitExceeded }
            retained += request.byteCount
        }
        self.requests = requests.sorted {
            let left = $0.byteCount - (sizes[$0.filename] ?? 0)
            let right = $1.byteCount - (sizes[$1.filename] ?? 0)
            return left == right ? $0.filename < $1.filename : left < right
        }
        retainedByteCount = retained
    }
}
