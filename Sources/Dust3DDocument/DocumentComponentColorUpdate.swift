/// One bounded component color replacement in an atomic document batch.
public struct DocumentComponentColorUpdate: Equatable, Sendable {
    /// Same maximum as the document's existing supported component hierarchy.
    public static let maximumBatchCount = ComponentHierarchy.maximumCount

    public let componentID: String
    public let color: DocumentColor?

    /// Replace one exact component's explicit color; nil removes the attribute.
    /// - Parameters: `componentID` is validated against the complete hierarchy before any batch mutation.
    ///   `color` contains already bounded eight-bit channels, or nil to retain the inherited default.
    public init(componentID: String, color: DocumentColor?) {
        self.componentID = componentID
        self.color = color
    }
}
