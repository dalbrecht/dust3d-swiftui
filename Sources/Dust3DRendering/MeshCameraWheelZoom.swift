import Foundation

/// Cumulative signed wheel steps for one mounted preview camera.
package struct MeshCameraWheelZoom: Sendable {
    private let epoch = UUID()
    private var total = 0

    package init() {}

    package mutating func append(step: Int) {
        total = total &+ step
    }

    /// A new viewport adopts the baseline without replaying prior input.
    package func steps(since previous: Self?) -> Int {
        guard let previous else { return 0 }
        return epoch == previous.epoch ? total &- previous.total : total
    }
}
