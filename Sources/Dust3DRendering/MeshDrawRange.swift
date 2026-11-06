import Foundation

/// A span addresses the existing full vertex buffer; it never changes its bounds.
struct MeshDrawRange: Sendable {
    let vertexStart: Int
    let vertexCount: Int

    static let empty = MeshDrawRange(vertexStart: 0, vertexCount: 0)

    private init(vertexStart: Int, vertexCount: Int) {
        self.vertexStart = vertexStart
        self.vertexCount = vertexCount
    }

    init(vertexCount: Int, range: Range<Int>?) throws {
        guard vertexCount >= 0 else {
            throw RendererError.unavailable("The mesh draw range has an invalid buffer length.")
        }
        guard let range else {
            self.init(vertexStart: 0, vertexCount: vertexCount)
            return
        }
        guard range.lowerBound >= 0, range.upperBound <= vertexCount,
            range.lowerBound.isMultiple(of: 3), range.upperBound.isMultiple(of: 3)
        else {
            throw RendererError.unavailable(
                "The mesh draw range must select complete triangles within its vertex buffer.")
        }
        self.init(vertexStart: range.lowerBound, vertexCount: range.count)
    }
}

/// Reject malformed input by clearing its draw permission before validation.
struct MeshDrawRangeState {
    private(set) var span = MeshDrawRange.empty
    private(set) var isValid = false

    mutating func update(vertexCount: Int, range: Range<Int>?, isIndexed: Bool = false) throws {
        span = .empty
        isValid = false
        guard !isIndexed || range == nil else {
            throw RendererError.unavailable("Partial triangle drawing requires an expanded mesh.")
        }
        span = try MeshDrawRange(vertexCount: vertexCount, range: range)
        isValid = true
    }
}

/// Range-only changes replace diagnostics without rebuilding GPU geometry.
struct MeshDrawRangeRequestState {
    private var range: Range<Int>?
    private var meshRevision: Int?
    private var hasReportedError = false
    private var epoch = UUID()

    @discardableResult
    mutating func update(range: Range<Int>?, meshRevision: Int) -> Bool {
        guard self.range != range || self.meshRevision != meshRevision else { return false }
        self.range = range
        self.meshRevision = meshRevision
        epoch = UUID()
        hasReportedError = false
        return true
    }

    mutating func captureFailure() -> UUID? {
        guard !hasReportedError else { return nil }
        hasReportedError = true
        return epoch
    }

    mutating func succeeded() { hasReportedError = false }
    func accepts(_ capturedEpoch: UUID) -> Bool { capturedEpoch == epoch }
}
