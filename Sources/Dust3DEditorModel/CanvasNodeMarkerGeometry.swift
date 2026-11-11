/// Node marker dimensions shared by the editing and companion profiles.
package struct CanvasNodeMarkerGeometry {
    package static let centerDiameter: Double = 12
    package let outlineDiameter: Double
    package let outlineWidth: Double

    var marqueeRadius: Double {
        max(Self.centerDiameter, outlineDiameter) / 2
    }

    package init(projectedDiameter: Double, selected: Bool, hovered: Bool) {
        outlineWidth = hovered ? 3 : (selected ? 2 : 1)
        // Leave half a point between the opaque center and the inside of the hover stroke.
        let minimumDiameter = hovered ? Self.centerDiameter + outlineWidth + 1 : 8
        outlineDiameter = max(minimumDiameter, min(projectedDiameter, 600))
    }
}
