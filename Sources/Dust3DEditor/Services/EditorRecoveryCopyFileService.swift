import Dust3DEditorModel
import Foundation
import os

/// Writes accepted archives outside the editing actor; receipts are best-effort secondary records.
actor EditorRecoveryCopyFileService: EditorRecoveryCopyWriting {
    private static let receiptName = "latest-recovery.json"
    private static let maximumReceiptBytes = 64 * 1024
    private let directory: URL
    private let maximumBytes: Int
    private let writeData: @Sendable (Data, URL) throws -> Void
    private let isSupportedIdentity: Bool

    init(bundleIdentifier: String?) {
        let identifier = bundleIdentifier ?? ""
        isSupportedIdentity = EditorRecoveryCopyChannel.isSupportedIdentity(identifier)
        directory =
            (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support"))
            .appendingPathComponent(identifier).appendingPathComponent("RecoveryCopies", isDirectory: true)
        maximumBytes = RecoveryCopyPlan.maximumRetainedBytes
        writeData = { try $0.write(to: $1, options: .atomic) }
    }

    init(
        directory: URL, maximumBytes: Int = RecoveryCopyPlan.maximumRetainedBytes,
        writeData: @escaping @Sendable (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }
    ) {
        self.directory = directory
        isSupportedIdentity = true
        self.maximumBytes = maximumBytes
        self.writeData = writeData
    }

    func write(captures: [EditorRecoveryCapture], requestID: UUID) async throws -> EditorRecoveryReport {
        try Task.checkCancellation()
        guard isSupportedIdentity else { throw EditorRecoveryCopyError.unsafeIdentity }
        guard captures.count <= RecoveryCopyPlan.maximumDocuments else { throw RecoveryCopyPlanError.tooManyDocuments }
        try prepareDirectory()
        var snapshots: [EditorRecoverySnapshot] = []
        var report = EditorRecoveryReport(requestID: requestID, requestedCount: captures.count)
        for capture in captures {
            switch capture {
            case .snapshot(let snapshot): snapshots.append(snapshot)
            case .failure(let failure): report.failures.append(failure)
            }
        }
        let plan = try RecoveryCopyPlan(
            requests: snapshots.map(\.request), inventory: inventory(), maximumBytes: maximumBytes)
        // Planning validates uniqueness before dictionary construction.
        let byIdentifier = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.request.documentID, $0) })
        for request in plan.requests {
            do {
                try Task.checkCancellation()
                guard let snapshot = byIdentifier[request.documentID] else {
                    throw EditorRecoveryCopyError.identityMismatch
                }
                let destination = directory.appendingPathComponent(request.filename)
                try writeData(snapshot.document.encoded(), destination)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
                report.copied.append(request)
            } catch {
                report.failures.append(.init(documentID: request.documentID, cause: error))
            }
        }
        do {
            let data = try JSONEncoder().encode(Receipt(report: report))
            guard data.count <= Self.maximumReceiptBytes else { throw RecoveryCopyPlanError.storageLimitExceeded }
            let destination = directory.appendingPathComponent(Self.receiptName)
            try writeData(data, destination)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        } catch {
            report.receiptError = error
        }
        return report
    }

    private func prepareDirectory() throws {
        guard directory.isFileURL else { throw EditorRecoveryCopyError.unsafeLocation }
        let manager = FileManager.default
        do {
            let values = try directory.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard values.isSymbolicLink == false, values.isDirectory == true else {
                throw EditorRecoveryCopyError.unsafeLocation
            }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            try manager.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private func inventory() throws -> [RecoveryCopyInventoryEntry] {
        let enumerationFailure = OSAllocatedUnfairLock<(any Error)?>(initialState: nil)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard
            let enumerator = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsSubdirectoryDescendants],
                errorHandler: { _, error in
                    enumerationFailure.withLock { $0 = error }
                    return false
                }
            )
        else { throw EditorRecoveryCopyError.unsafeLocation }
        var entries: [RecoveryCopyInventoryEntry] = []
        var visited = 0
        while let next = enumerator.nextObject() {
            visited += 1
            guard visited <= RecoveryCopyPlan.maximumFiles + 1 else { throw RecoveryCopyPlanError.tooManyFiles }
            guard let url = next as? URL else { throw RecoveryCopyPlanError.invalidInventory }
            let values = try url.resourceValues(forKeys: keys)
            guard values.isSymbolicLink == false, values.isRegularFile == true,
                let size = values.fileSize, size >= 0
            else { throw RecoveryCopyPlanError.invalidInventory }
            if url.lastPathComponent == Self.receiptName {
                guard size <= Self.maximumReceiptBytes else { throw RecoveryCopyPlanError.invalidInventory }
            } else {
                guard entries.count < RecoveryCopyPlan.maximumFiles else { throw RecoveryCopyPlanError.tooManyFiles }
                entries.append(.init(name: url.lastPathComponent, byteCount: size))
            }
        }
        if let error = enumerationFailure.withLock({ $0 }) { throw error }
        return entries
    }

    private struct Receipt: Encodable {
        let version = 1
        let requestID: UUID
        let date = Date()
        let requestedCount: Int
        let status: String
        let copied: [Copy]
        let failures: [Failure]

        init(report: EditorRecoveryReport) {
            requestID = report.requestID
            requestedCount = report.requestedCount
            status =
                report.requestedCount == 0
                ? "noDocuments" : report.failures.isEmpty ? "completed" : report.copied.isEmpty ? "failed" : "partial"
            copied = report.copied.map {
                Copy(documentID: $0.documentID, revision: $0.revision, filename: $0.filename, byteCount: $0.byteCount)
            }
            failures = report.failures.map { Failure(documentID: $0.documentID, cause: $0.cause) }
        }
    }

    private struct Copy: Encodable {
        let documentID: UUID
        let revision: Int
        let filename: String
        let byteCount: Int
    }

    private struct Failure: Encodable {
        let documentID: UUID?
        let description: String
        let isTruncated: Bool

        init(documentID: UUID?, cause: any Error) {
            self.documentID = documentID
            let text = String(describing: cause)
            var bounded = String(decoding: text.utf8.prefix(1024), as: UTF8.self)
            while bounded.utf8.count > 1024 { bounded.removeLast() }
            description = bounded
            isTruncated = text.utf8.count > 1024
        }
    }
}
