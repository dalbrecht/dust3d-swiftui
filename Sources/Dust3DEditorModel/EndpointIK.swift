import simd

/// The unconstrained cyclic coordinate descent used by Qt's endpoint drag.
enum EndpointIK {
    static func solve(_ chain: [SIMD3<Double>], toward target: SIMD3<Double>) throws -> [SIMD3<Double>] {
        guard chain.count > 1 else { return chain }
        var positions = chain
        var lastDistance = 0.0
        for _ in 0..<4 {
            try Task.checkCancellation()
            let distance = simd_length_squared(positions[positions.count - 1] - target)
            if distance <= 0.000001 || (lastDistance > 0 && abs(distance - lastDistance) <= 0.000001) {
                break
            }
            lastDistance = distance
            try sweep(&positions, toward: target)
        }
        return positions
    }

    private static func sweep(_ positions: inout [SIMD3<Double>], toward target: SIMD3<Double>) throws {
        let endIndex = positions.count - 1
        let identity = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)
        var rotations = Array(repeating: identity, count: endIndex)
        var endpoint = positions[endIndex]

        // Downstream joints never move an upstream pivot. Record the rotations while tracking only the endpoint.
        for index in (0..<endIndex).reversed() {
            try Task.checkCancellation()
            let pivot = positions[index]
            let rotation = rotation(from: endpoint - pivot, to: target - pivot)
            rotations[index] = rotation
            endpoint = pivot + rotation.act(endpoint - pivot)
        }

        // Apply each joint's ancestor transforms once instead of rotating every suffix separately.
        var accumulated = identity
        var translation = SIMD3<Double>.zero
        for index in 0..<endIndex {
            try Task.checkCancellation()
            let pivot = positions[index]
            let rotation = rotations[index]
            positions[index] = accumulated.act(pivot) + translation
            translation += accumulated.act(pivot - rotation.act(pivot))
            accumulated = simd_normalize(accumulated * rotation)
        }
        positions[endIndex] = endpoint
    }

    private static func rotation(from: SIMD3<Double>, to: SIMD3<Double>) -> simd_quatd {
        let identity = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)
        let fromLength = simd_length(from)
        let toLength = simd_length(to)
        guard fromLength > 1e-12, toLength > 1e-12 else { return identity }
        let start = from / fromLength
        let end = to / toLength
        let dot = simd_dot(start, end)
        if dot >= 1 - 1e-15 { return identity }
        if dot <= -1 + 1e-15 {
            let reference: SIMD3<Double> = abs(start.x) < 0.9 ? [1, 0, 0] : [0, 1, 0]
            return simd_quatd(angle: .pi, axis: simd_normalize(simd_cross(start, reference)))
        }
        let axis = simd_cross(start, end)
        return simd_normalize(simd_quatd(ix: axis.x, iy: axis.y, iz: axis.z, r: 1 + dot))
    }
}
