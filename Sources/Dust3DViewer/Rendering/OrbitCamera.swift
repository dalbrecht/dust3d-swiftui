import simd

struct OrbitCamera {
    var yaw: Float = -0.35
    var pitch: Float = 0.15
    var distance: Float = 3

    mutating func orbit(horizontal: Float, vertical: Float) {
        yaw += horizontal * 0.01
        pitch = min(1.5, max(-1.5, pitch + vertical * 0.01))
    }

    mutating func zoom(delta: Float) {
        distance = min(20, max(1.25, distance * exp(-delta * 0.03)))
    }

    var rotation: simd_float4x4 {
        simd_float4x4(simd_quatf(angle: pitch, axis: SIMD3(1, 0, 0)))
            * simd_float4x4(simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)))
    }

    func transform(aspect: Float) -> simd_float4x4 {
        let scale: Float = 1 / tan(.pi / 8)
        let near: Float = 0.01
        let far: Float = 100
        let projection = simd_float4x4(
            columns: (
                SIMD4(scale / max(aspect, 0.01), 0, 0, 0),
                SIMD4(0, scale, 0, 0),
                SIMD4(0, 0, far / (near - far), -1),
                SIMD4(0, 0, near * far / (near - far), 0)
            ))
        var view = matrix_identity_float4x4
        view.columns.3.z = -distance
        return projection * view * rotation
    }
}
