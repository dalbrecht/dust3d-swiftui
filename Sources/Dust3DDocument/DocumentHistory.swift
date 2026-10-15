/// Value-based undo history. The app owns one history per document; no UI framework is required.
public struct DocumentHistory: Sendable {
    public private(set) var document: Dust3DDocument
    private var undoStack: [Dust3DDocument] = []
    private var redoStack: [Dust3DDocument] = []
    private var transactionStart: Dust3DDocument?
    private var transactionNodes: Set<String> = []
    private var saved: Dust3DDocument
    private let maximumEntries: Int
    private let maximumUndoBytes: Int

    public init(document: Dust3DDocument, maximumEntries: Int = 100, maximumUndoBytes: Int = 64 * 1024 * 1024) {
        self.document = document
        self.saved = document
        self.maximumEntries = max(1, maximumEntries)
        self.maximumUndoBytes = max(1, maximumUndoBytes)
    }

    public var isDirty: Bool { document.encoded() != saved.encoded() }
    public var canUndo: Bool { transactionStart == nil && !undoStack.isEmpty }
    public var canRedo: Bool { transactionStart == nil && !redoStack.isEmpty }

    /// Validate and commit a command. A rejected or no-op command preserves history and redo.
    public mutating func apply(_ command: DocumentCommand) throws {
        let next = try document.applying(command)
        guard next.encoded() != document.encoded() else { return }
        guard document.encoded().count <= maximumUndoBytes, next.encoded().count <= maximumUndoBytes else {
            throw DocumentError.limitExceeded
        }
        if transactionStart == nil {
            redoStack.removeAll()
            pushUndo(document)
        } else {
            switch command {
            case .setNode(let id, _, _): transactionNodes.insert(id)
            }
        }
        document = next
    }

    /// Group continuous edits into one undo record. Nested transactions are rejected.
    public mutating func beginTransaction() throws {
        guard transactionStart == nil else { throw DocumentError.transactionAlreadyOpen }
        transactionStart = document
    }

    public mutating func endTransaction() throws {
        guard let start = transactionStart else { throw DocumentError.noTransaction }
        let unchanged = try transactionNodes.allSatisfy { try start.node(id: $0) == document.node(id: $0) }
        if unchanged {
            document = start
        } else {
            redoStack.removeAll()
            pushUndo(start)
        }
        transactionStart = nil
        transactionNodes.removeAll()
    }

    public mutating func cancelTransaction() {
        guard let start = transactionStart else { return }
        document = start
        transactionStart = nil
        transactionNodes.removeAll()
    }

    @discardableResult public mutating func undo() -> Bool {
        guard transactionStart == nil, let previous = undoStack.popLast() else { return false }
        redoStack.append(document)
        document = previous
        trimHistory()
        return true
    }

    @discardableResult public mutating func redo() -> Bool {
        guard transactionStart == nil, let next = redoStack.popLast() else { return false }
        pushUndo(document)
        document = next
        return true
    }

    /// Record the exact snapshot written successfully, even if newer edits arrived during the write.
    public mutating func markSaved(_ writtenDocument: Dust3DDocument) { saved = writtenDocument }

    private mutating func pushUndo(_ value: Dust3DDocument) {
        undoStack.append(value)
        trimHistory()
    }

    private mutating func trimHistory() {
        while undoStack.count + redoStack.count > maximumEntries
            || (undoStack + redoStack).reduce(0, { $0 + $1.encoded().count }) > maximumUndoBytes
        {
            if !undoStack.isEmpty {
                undoStack.removeFirst()
            } else {
                redoStack.removeFirst()
            }
        }
    }
}
