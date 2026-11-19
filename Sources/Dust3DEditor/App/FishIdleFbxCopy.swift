import Foundation

enum FishIdleFbxCopy {
    static func outputBudget(_ limits: FishIdleCopyLimits) -> Int {
        min(limits.nativeBytes, limits.swiftBytes, limits.combinedBytes / 2, 256 * 1024 * 1024)
    }

    static func copy(byteCount: Int, limits: FishIdleCopyLimits, read: (Int) throws -> Data) throws -> Data {
        try Task.checkCancellation()
        guard byteCount <= outputBudget(limits) else { throw FishIdleCopyError.payloadLimit }
        let header = Data("Kaydara FBX Binary  \0\u{1a}\0".utf8) + Data([0xe8, 0x1c, 0, 0])
        guard byteCount > header.count else { throw FishIdleCopyError.nativeReceipt }
        let bytes = try read(byteCount)
        try Task.checkCancellation()
        guard bytes.count == byteCount, bytes.starts(with: header) else { throw FishIdleCopyError.nativeReceipt }
        return bytes
    }
}
