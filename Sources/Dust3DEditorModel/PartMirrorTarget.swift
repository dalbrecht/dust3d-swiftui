import Dust3DDocument

/// An inspector edit belongs to one exact owner and the originating document, selection and constraint epochs.
public struct PartMirrorTarget: Sendable {
    private let context: CanvasAdjustmentTarget
    public let partID: String?

    /// Capture the exact currently inspected part without normalizing its stored identity.
    public init(snapshot: EditorSnapshot, partID: String) {
        context = CanvasAdjustmentTarget(snapshot: snapshot)
        self.partID = snapshot.mirrorInspectorPart.flatMap { $0.id.utf8.elementsEqual(partID.utf8) ? $0.id : nil }
    }

    public func isCurrent(in snapshot: EditorSnapshot) -> Bool {
        guard let partID, context.isCurrent(in: snapshot), let part = snapshot.mirrorInspectorPart else { return false }
        return part.id.utf8.elementsEqual(partID.utf8)
    }
}

public enum PartMirrorError: Error, Equatable, Sendable { case staleTarget }

extension EditorSnapshot {
    /// Inspect one Model owner directly, including shared component links.
    public var mirrorInspectorPart: DocumentPart? {
        guard let part = selectedPart ?? selectedLinkedComponentPart,
            part.target == .model
        else { return nil }
        return part
    }
}
