/// Node marker dimensions shared by the editing and companion profiles.
struct CanvasNodeMarkerGeometry {
    static let centerDiameter: Double = 12
    let outlineDiameter: Double
    let outlineWidth: Double

    static func hitRadius(projectedDiameter: Double) -> Double {
        let marker = Self(projectedDiameter: projectedDiameter, selected: false, hovered: false)
        return max(18, marker.outlineDiameter / 2)
    }

    init(projectedDiameter: Double, selected: Bool, hovered: Bool) {
        outlineWidth = hovered ? 3 : (selected ? 2 : 1)
        // Leave half a point between the opaque center and the inside of the hover stroke.
        let minimumDiameter = hovered ? Self.centerDiameter + outlineWidth + 1 : 8
        outlineDiameter = max(minimumDiameter, min(projectedDiameter, 600))
    }
}
