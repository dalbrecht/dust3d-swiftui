import Foundation

/// Trusted, process-local identities for preview inputs; never serialized into the archive.
/// Equal identities within one history mean commands preserved the corresponding input.
public struct DocumentPreviewIdentity: Equatable, Sendable {
    public private(set) var geometry = UUID()
    public private(set) var materials = UUID()

    mutating func advance(for command: DocumentCommand) {
        switch command {
        case .createAnimation, .setAnimationName, .setAnimationType, .setAnimationParameter,
            .duplicateAnimation, .deleteAnimation, .setRigType, .setHeadHasEyelids, .setEdgeBoneName,
            .setPartName, .setComponentName, .setReferenceImagePNG:
            break
        case .setPartState(_, let property, _) where property != .disabled:
            break
        case .setPartMaterial, .setComponentColorImage, .importComponentColorImage:
            materials = UUID()
        default:
            geometry = UUID()
            materials = UUID()
        }
    }
}

/// Value-based undo history. The app owns one history per document; no UI framework is required.
public struct DocumentHistory: Sendable {
    public private(set) var document: Dust3DDocument
    /// Preview inputs follow accepted commands and history, independently of save/dirty state.
    public private(set) var previewIdentity = DocumentPreviewIdentity()
    private struct Entry: Sendable {
        let document: Dust3DDocument
        let previewIdentity: DocumentPreviewIdentity
    }
    private var entry: Entry { Entry(document: document, previewIdentity: previewIdentity) }
    private var undoStack: [Entry] = []
    private var redoStack: [Entry] = []
    private var transactionStart: Entry?
    private var transactionRequiresModelComparison = false
    private var transactionChangesAssets = false
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
            pushUndo(entry)
        } else {
            switch command {
            case .setNode(let id, _, _): transactionNodes.insert(id)
            case .setReferenceImagePNG, .pasteNodes, .importComponentColorImage: transactionChangesAssets = true
            default: transactionRequiresModelComparison = true
            }
        }
        document = next
        previewIdentity.advance(for: command)
    }

    /// Group continuous edits into one undo record. Nested transactions are rejected.
    public mutating func beginTransaction() throws {
        guard transactionStart == nil else { throw DocumentError.transactionAlreadyOpen }
        transactionStart = entry
    }

    public mutating func endTransaction() throws {
        guard let start = transactionStart else { throw DocumentError.noTransaction }
        let unchanged =
            try transactionChangesAssets
            ? start.document.hasSameContents(as: document)
            : transactionRequiresModelComparison
                ? start.document.hasSameModel(as: document)
                : transactionNodes.allSatisfy { try start.document.node(id: $0) == document.node(id: $0) }
        if unchanged {
            document = start.document
            previewIdentity = start.previewIdentity
        } else {
            redoStack.removeAll()
            pushUndo(start)
        }
        transactionStart = nil
        transactionNodes.removeAll()
        transactionRequiresModelComparison = false
        transactionChangesAssets = false
    }

    public mutating func cancelTransaction() {
        guard let start = transactionStart else { return }
        document = start.document
        previewIdentity = start.previewIdentity
        transactionStart = nil
        transactionNodes.removeAll()
        transactionRequiresModelComparison = false
        transactionChangesAssets = false
    }

    @discardableResult public mutating func undo() -> Bool {
        guard transactionStart == nil, let previous = undoStack.popLast() else { return false }
        redoStack.append(entry)
        document = previous.document
        previewIdentity = previous.previewIdentity
        trimHistory()
        return true
    }

    @discardableResult public mutating func redo() -> Bool {
        guard transactionStart == nil, let next = redoStack.popLast() else { return false }
        pushUndo(entry)
        document = next.document
        previewIdentity = next.previewIdentity
        return true
    }

    /// Record the exact snapshot written successfully, even if newer edits arrived during the write.
    public mutating func markSaved(_ writtenDocument: Dust3DDocument) { saved = writtenDocument }

    private mutating func pushUndo(_ value: Entry) {
        undoStack.append(value)
        trimHistory()
    }

    private mutating func trimHistory() {
        while undoStack.count + redoStack.count > maximumEntries
            || (undoStack + redoStack).reduce(0, { $0 + $1.document.encoded().count }) > maximumUndoBytes
        {
            if !undoStack.isEmpty {
                undoStack.removeFirst()
            } else {
                redoStack.removeFirst()
            }
        }
    }
}
