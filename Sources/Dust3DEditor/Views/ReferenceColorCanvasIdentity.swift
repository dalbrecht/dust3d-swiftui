import Dust3DEditorModel
import Foundation

/// Exact logical projection/viewport identity; neither Retina scale nor cached image dimensions are inputs.
struct ReferenceColorCanvasIdentity: Equatable, Sendable {
    let plane: EditingPlane
    let scale: Double
    let origin: CanvasPoint
    let width: Double
    let height: Double

    init(projection: CanvasProjection, width: Double, height: Double) {
        plane = projection.plane
        scale = projection.scale
        origin = projection.point(for: .init(x: 0, y: 0, z: 0))
        self.width = width
        self.height = height
    }
    var isValid: Bool {
        [scale, origin.x, origin.y, width, height].allSatisfy(\.isFinite) && scale > 0 && width > 0 && height > 0
    }
}

struct PreparedReferenceColors: Sendable {
    let sourceID: UUID
    let canvas: ReferenceColorCanvasIdentity
    let result: ReferenceColorRasterResult
    let layout: ReferenceColorSamplingLayout
}
