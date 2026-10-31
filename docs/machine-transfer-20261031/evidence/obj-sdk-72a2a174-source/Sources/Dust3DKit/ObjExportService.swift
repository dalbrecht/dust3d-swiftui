import Foundation

/// Background export generation from an immutable source snapshot, with no file or UI state.
public protocol ObjExporting: Sendable {
    /// Generate owned OBJ data off the main actor.
    /// - Parameters: data is the exact source snapshot; options bound independent ownership layers.
    /// - Returns: Owned geometry-only OBJ and original compatibility warnings.
    /// - Throws: Original export failure or cancellation; synchronous native phases are not preemptible.
    func encode(data: Data, options: ObjExportOptions) async throws -> ObjExport
}

/// Serial background CPU export; no native pointer crosses an actor suspension.
public actor ObjExportService: ObjExporting {
    private let operation: any ObjExportOperation

    /// Create a background exporter without retained document or mesh state.
    public init() { operation = NativeObjExportOperation() }
    init(operation: any ObjExportOperation) { self.operation = operation }

    /// Generate from the supplied snapshot and reject cancelled publication.
    /// - Parameters: data is complete archive bytes; options bound the retained result.
    /// - Returns: Independent immutable OBJ data.
    /// - Throws: Original operation error or CancellationError.
    /// - Example: `let output = try await ObjExportService().encode(data: archive)`.
    public func encode(data: Data, options: ObjExportOptions = .init()) async throws -> ObjExport {
        try Task.checkCancellation()
        let output = try operation.encode(data: data, options: options)
        try Task.checkCancellation()
        return output
    }
}

protocol ObjExportOperation: Sendable {
    func encode(data: Data, options: ObjExportOptions) throws -> ObjExport
}
struct NativeObjExportOperation: ObjExportOperation {
    func encode(data: Data, options: ObjExportOptions) throws -> ObjExport {
        try ObjExporter.encode(data: data, options: options)
    }
}
