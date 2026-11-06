import Foundation

/// A pending click becomes an irreversible camera drag at four view points.
struct MeshPickGesture {
    struct Lease: Equatable {
        let pickingRevision: UUID
        let cameraRevision: UUID
    }
    private var origin: SIMD2<Float>?
    private var previous = SIMD2<Float>.zero
    private var lease: Lease?
    private var dragging = false
    private var allowsClick = true

    mutating func begin(at point: SIMD2<Float>, lease: Lease) {
        origin = point
        previous = point
        self.lease = lease
        dragging = false
        allowsClick = true
    }
    /// Pan intent must never turn into a pick, even below the drag threshold.
    mutating func disallowClick() { allowsClick = false }

    mutating func cancel() {
        origin = nil
        lease = nil
        dragging = false
    }
    private mutating func accepts(_ current: Lease) -> Bool {
        guard let lease, lease.pickingRevision == current.pickingRevision,
            dragging || lease.cameraRevision == current.cameraRevision
        else {
            cancel()
            return false
        }
        return true
    }
    mutating func drag(to point: SIMD2<Float>, lease: Lease) -> SIMD2<Float>? {
        guard let origin, accepts(lease) else { return nil }
        let displacement = point - origin
        if !dragging {
            guard displacement.x * displacement.x + displacement.y * displacement.y >= 16 else { return nil }
            dragging = true
        }
        let delta = point - previous
        previous = point
        return delta
    }
    mutating func finish(at point: SIMD2<Float>, lease: Lease) -> SIMD2<Float>? {
        defer { cancel() }
        guard let origin, accepts(lease), !dragging, allowsClick else { return nil }
        let displacement = point - origin
        guard displacement.x * displacement.x + displacement.y * displacement.y < 16 else { return nil }
        return point
    }
}
