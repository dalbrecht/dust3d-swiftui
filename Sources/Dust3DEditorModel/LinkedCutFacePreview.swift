import Dust3DDocument
import Foundation

/// An authored Front outline for one exact linked part, without generating a mesh or substituting a preset.
package enum LinkedCutFacePreview {
    package static let maximumNodes = 1024

    private struct Vertex {
        let center: SIMD2<Double>
        let radius: Double
    }

    package static func contour(partID: String, snapshot: EditorSnapshot) -> [CanvasPoint]? {
        guard snapshot.parts.contains(where: { $0.id.utf8.elementsEqual(partID.utf8) }) else { return nil }
        var vertices: [Data: Vertex] = [:]
        for node in snapshot.nodes where node.partID?.utf8.elementsEqual(partID.utf8) == true {
            let value = node.value
            guard vertices.count < maximumNodes, Float(value.position.x).isFinite, Float(value.position.y).isFinite
            else { return nil }
            let vertex = Vertex(center: SIMD2(value.position.x, -value.position.y), radius: value.radius)
            guard vertices.updateValue(vertex, forKey: Data(node.id.utf8)) == nil else { return nil }
        }
        guard vertices.count >= 2 else { return nil }

        var neighbors: [Data: [Data]] = [:]
        for edge in snapshot.edges where edge.partID?.utf8.elementsEqual(partID.utf8) == true {
            let from = Data(edge.fromID.utf8)
            let to = Data(edge.toID.utf8)
            guard from != to, vertices[from] != nil, vertices[to] != nil,
                neighbors[from, default: []].count < 2, neighbors[to, default: []].count < 2,
                !neighbors[from, default: []].contains(to)
            else { return nil }
            neighbors[from, default: []].append(to)
            neighbors[to, default: []].append(from)
        }
        guard neighbors.count == vertices.count else { return nil }
        let endpoints = neighbors.compactMap { $0.value.count == 1 ? $0.key : nil }
        let isRing = endpoints.isEmpty
        guard isRing ? vertices.count >= 3 : endpoints.count == 2 else { return nil }
        let candidates = (isRing ? Array(vertices.keys) : endpoints).sorted { $0.lexicographicallyPrecedes($1) }

        // Match the linked profile's start direction, with exact source order breaking angular ties.
        let center =
            candidates.compactMap { vertices[$0]?.center }.reduce(SIMD2<Double>.zero, +)
            / Double(candidates.count)
        var bestScore = -Double.infinity
        var next = candidates.first
        for candidate in candidates {
            guard let vertex = vertices[candidate], let direction = unit(vertex.center - center) else { continue }
            let score = -direction.x - direction.y
            if score > bestScore {
                bestScore = score
                next = candidate
            }
        }
        var ordered: [Vertex] = []
        var visited: Set<Data> = []
        while let id = next, let vertex = vertices[id], visited.insert(id).inserted {
            ordered.append(vertex)
            next = neighbors[id]?.first { !visited.contains($0) }
        }
        guard ordered.count == vertices.count else { return nil }
        if isRing { return normalized(ordered.map(\.center)) }
        guard let outline = openOutline(ordered) else { return nil }
        return normalized(outline)
    }

    private static func openOutline(_ vertices: [Vertex]) -> [SIMD2<Double>]? {
        var tangents: [SIMD2<Double>] = []
        for (previous, next) in zip(vertices, vertices.dropFirst()) {
            guard let direction = unit(next.center - previous.center) else { return nil }
            tangents.append(direction)
        }
        var firstSide: [SIMD2<Double>] = []
        var secondSide: [SIMD2<Double>] = []
        for (index, vertex) in vertices.enumerated() {
            let previous = tangents[max(0, index - 1)]
            let next = tangents[min(index, tangents.count - 1)]
            guard Float(vertex.radius).isFinite, Float(vertex.radius) > 0,
                let tangent = unit(previous + next)
            else { return nil }
            let offset = SIMD2(tangent.y, -tangent.x) * vertex.radius
            firstSide.append(vertex.center + offset)
            secondSide.append(vertex.center - offset)
        }
        return firstSide + secondSide.reversed()
    }

    private static func unit(_ vector: SIMD2<Double>) -> SIMD2<Double>? {
        let magnitude = hypot(vector.x, vector.y)
        guard magnitude.isFinite, magnitude > 0 else { return nil }
        return vector / magnitude
    }

    private static func normalized(_ points: [SIMD2<Double>]) -> [CanvasPoint]? {
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let xMin = xs.min(), let xMax = xs.max(), let yMin = ys.min(), let yMax = ys.max() else { return nil }
        let span = max(xMax - xMin, yMax - yMin)
        guard span.isFinite, span > 0 else { return nil }
        let center = SIMD2((xMin + xMax) / 2, (yMin + yMax) / 2)
        var contour = points.map { ($0 - center) / span * 2 }

        // Preserve the first vertex and correct winding by the sum of adjacent turn signs.
        var turns = 0
        for index in contour.indices {
            let first = contour[(index + 1) % contour.count] - contour[index]
            let second = contour[(index + 2) % contour.count] - contour[index]
            let cross = first.x * second.y - first.y * second.x
            if cross > 0 { turns += 1 } else if cross < 0 { turns -= 1 }
        }
        if turns <= 0 { contour[1...].reverse() }
        return contour.map { CanvasPoint(x: $0.x, y: $0.y) }
    }
}
