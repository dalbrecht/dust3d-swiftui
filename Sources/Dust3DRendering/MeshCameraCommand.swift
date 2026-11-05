import Foundation

/// One presentation-only camera activation; reuse an identity across view refreshes.
public struct MeshCameraCommand: Sendable {
    /// Discrete orbit, screen-space pan, and bounded zoom directions.
    public enum Action: Sendable {
        case orbitLeft, orbitRight, orbitUp, orbitDown
        case panLeft, panRight, panUp, panDown
        case zoomIn, zoomOut
    }

    let id = UUID()
    let action: Action

    /// Create a fresh activation. Repeated actions need separate command values.
    /// - Parameter action: The requested camera movement.
    public init(_ action: Action) { self.action = action }
}
