import Dust3DDocument

/// The pinned core's CutFaceToPoints outlines in the Qt preview's centered projection.
package enum CutFacePresetPreview {
    package static func points(for preset: CutFacePreset, width: Double, height: Double) -> [CanvasPoint] {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return [] }
        let scale = min(width, height) * 0.35
        return vertices(for: preset).map { vertex in
            CanvasPoint(
                x: width / 2 + scale * Double(vertex.x),
                y: height / 2 - scale * Double(vertex.y))
        }
    }

    private static func vertices(for preset: CutFacePreset) -> [(x: Float, y: Float)] {
        // Keep the engine's Float precision and winding, including its asymmetric profiles.
        switch preset {
        case .quad: [(-1, -1), (1, -1), (1, 1), (-1, 1)]
        case .triangle: [(-1.1527, -0.6655), (1.1527, -0.6655), (0, 1.33447)]
        case .pentagon: [(-0.6498, -0.8944), (0.6498, -0.8944), (1.05146, 0.34164), (0, 1.10557), (-1.05146, 0.34164)]
        case .hexagon: [(-0.577, -1), (0.577, -1), (1.1547, 0), (0.577, 1), (-0.577, 1), (-1.1547, 0)]
        }
    }
}
