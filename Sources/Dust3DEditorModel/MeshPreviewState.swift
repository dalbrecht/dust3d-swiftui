import Foundation

/// Transient generated-output state. Document edits, persistence and undo remain independent of preview failures.
public struct MeshPreviewState<Output: Sendable>: Sendable {
    public private(set) var value: Output?
    public private(set) var errorMessage: String?
    public private(set) var isGenerating = false
    public private(set) var revision = 0
    private var requestID: UUID?

    /// Creates an empty preview with no pending generation request.
    public init() {}

    /// Whether one caller-owned request may publish geometry and its auxiliary diagnostics.
    /// - Parameter requestID: Identity captured when generation began.
    /// - Returns: False for obsolete, completed, duplicate or cleared requests.
    public func isCurrent(requestID: UUID) -> Bool { self.requestID == requestID && isGenerating }

    /// Whether retained geometry predates the current pending or failed generation.
    public var isStale: Bool { value != nil && (isGenerating || errorMessage != nil) }

    /// Start a request, retaining any last successful output.
    /// - Parameters:
    ///   - requestID: New caller-owned request identity.
    ///   - preservingError: Keep the original failure visible during a repair until a current success or failure arrives.
    /// - Example: `preview.begin(requestID: id, preservingError: true)` for a repair retry.
    public mutating func begin(requestID: UUID, preservingError: Bool = false) {
        self.requestID = requestID
        if !preservingError { errorMessage = nil }
        isGenerating = true
    }

    /// Accepts output only for the active request. Obsolete or duplicate completions are ignored.
    public mutating func succeed(_ value: Output, requestID: UUID) {
        guard self.requestID == requestID else { return }
        self.value = value
        errorMessage = nil
        revision += 1
        finish()
    }

    /// Accepts a successful empty result only for the active request, removing retained geometry.
    /// - Parameter requestID: The identity supplied to `begin`; obsolete and duplicate results are ignored.
    /// - Example: `preview.succeedEmpty(requestID: requestID)` after a no-geometry engine result.
    public mutating func succeedEmpty(requestID: UUID) {
        guard self.requestID == requestID else { return }
        value = nil
        errorMessage = nil
        revision += 1
        finish()
    }

    /// Records a failure for the active request without discarding the last successful output.
    public mutating func fail(_ message: String, requestID: UUID) {
        guard self.requestID == requestID else { return }
        errorMessage = message
        finish()
    }

    /// Clears output and invalidates pending work when a document is empty, replaced, or closed.
    public mutating func clear() {
        value = nil
        errorMessage = nil
        finish()
    }

    private mutating func finish() {
        requestID = nil
        isGenerating = false
    }
}
