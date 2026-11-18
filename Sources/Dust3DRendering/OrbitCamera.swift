import simd

struct OrbitCamera {
    var yaw: Float = -0.35
    var pitch: Float = 0.15
    var distance: Float = 3

    private var screenOffset = SIMD2<Float>.zero

    init(yaw: Float = -0.35, pitch: Float = 0.15, distance: Float = 3) {
        self.yaw = yaw
        self.pitch = pitch
        self.distance = distance
    }

    mutating func pan(horizontal: Float, vertical: Float) {
        screenOffset = simd_clamp(
            screenOffset + SIMD2(horizontal, vertical), SIMD2(repeating: -1.5), SIMD2(repeating: 1.5))
    }

    mutating func orbit(horizontal: Float, vertical: Float) {
        yaw += horizontal * 0.01
        pitch = (pitch + vertical * 0.01).remainder(dividingBy: 2 * .pi)
    }

    mutating func zoom(delta: Float) {
        distance = min(20, max(1.25, distance * exp(-delta * 0.03)))
    }

    /// Pointer deltas use bottom-left view-point coordinates. Shift-pan follows
    /// the pointer in screen space; ordinary dragging retains the existing orbit.
    @discardableResult
    mutating func drag(by delta: SIMD2<Float>, viewport: SIMD2<Float>, pans: Bool) -> Bool {
        guard delta.x.isFinite, delta.y.isFinite else { return false }
        if pans {
            guard viewport.x.isFinite, viewport.y.isFinite, viewport.x > 0, viewport.y > 0 else { return false }
            func normalized(_ value: Float, size: Float) -> Float {
                let amount = Double(value) / Double(size) * 2
                // The full existing offset span is three. Larger deltas have
                // the same saturated result, and bounding before conversion
                // avoids Float overflow for small valid viewports.
                return Float(min(3, max(-3, amount)))
            }
            pan(horizontal: normalized(delta.x, size: viewport.x), vertical: normalized(delta.y, size: viewport.y))
        } else {
            orbit(horizontal: delta.x, vertical: -delta.y)
        }
        return true
    }

    /// AppKit magnification is an incremental scale delta. Reuse the zoom
    /// envelope while dividing camera distance by the positive factor 1 + delta.
    @discardableResult
    mutating func magnify(by magnification: Double) -> Bool {
        guard magnification.isFinite, magnification > -1 else { return false }
        zoom(delta: Float(log1p(magnification) / 0.03))
        return true
    }

    /// AppKit supplies counterclockwise degrees. This viewport maps that gesture
    /// to its existing left orbit, preserving pitch/pan rather than introducing roll.
    /// Reduce full turns before Float conversion to bound even extreme finite input.
    @discardableResult
    mutating func rotateGesture(by degrees: Double) -> Bool {
        guard degrees.isFinite else { return false }
        let turn = degrees.truncatingRemainder(dividingBy: 360)
        orbit(horizontal: -Float(turn * Double.pi / 180 / 0.01), vertical: 0)
        return true
    }

    var rotation: simd_float4x4 {
        simd_float4x4(simd_quatf(angle: pitch, axis: SIMD3(1, 0, 0)))
            * simd_float4x4(simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)))
    }

    func transform(aspect: Float) -> simd_float4x4 {
        // Geometry is normalized to a unit sphere; the narrower viewport axis must also contain that envelope.
        let boundedAspect = aspect.isFinite ? max(aspect, 0.01) : 1
        let viewingDistance = distance / min(boundedAspect, 1)
        let scale: Float = 1 / tan(.pi / 8)
        // Keep depth precision around the unit-sized model even when aspect fitting moves the camera far away.
        let near: Float = max(0.01, viewingDistance - 2)
        let far: Float = max(100, viewingDistance + 2)
        let projection = simd_float4x4(
            columns: (
                SIMD4(scale / boundedAspect, 0, 0, 0),
                SIMD4(0, scale, 0, 0),
                SIMD4(-screenOffset.x, -screenOffset.y, far / (near - far), -1),
                SIMD4(0, 0, near * far / (near - far), 0)
            ))
        var view = matrix_identity_float4x4
        view.columns.3.z = -viewingDistance
        return projection * view * rotation
    }
}
