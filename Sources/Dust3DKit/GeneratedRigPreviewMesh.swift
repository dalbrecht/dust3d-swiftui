import Foundation

extension GeneratedRig {
    /// Assemble the Qt rest preview in its common grounded frame, skeleton first.
    /// Selection colors the body by all four influences; only the renderer normalizes.
    /// - Parameters:
    ///   - skeleton: Unnormalized geometry from this rig, or nil when all axes are zero.
    ///   - selectedBoneName: Exact UTF-8 source name whose weights are displayed.
    ///   - boneColor: Platform palette for ordinary bones (alpha is forced to one).
    ///   - selectedBoneColor: Platform palette for selected bones.
    ///   - ringColor: Platform palette for capsule rings.
    /// - Returns: Copied triangles with opaque bones and body alpha 0.8.
    /// - Throws: Invalid source correspondence, nonfinite palette, or cancellation.
    package func previewMesh(
        skeleton: GeneratedRigSkeleton?, selectedBoneName: String = "",
        boneColor: SIMD4<Float>, selectedBoneColor: SIMD4<Float>, ringColor: SIMD4<Float>
    ) throws -> Mesh {
        func invalid() -> RigTemplateHierarchyError { .invalidMetadata("invalid generated rig preview correspondence") }
        guard influences.count == mesh.vertices.count,
            [boneColor, selectedBoneColor, ringColor].allSatisfy({ color in (0..<4).allSatisfy { color[$0].isFinite } })
        else { throw invalid() }
        if let skeleton {
            guard skeleton.boneNames.count == joints.count,
                zip(skeleton.boneNames, joints).allSatisfy({ Data($0.0.utf8) == Data($0.1.name.utf8) }),
                skeleton.vertices.count.isMultiple(of: 3),
                skeleton.vertices.allSatisfy({ vertex in
                    joints.indices.contains(vertex.boneIndex)
                        && (0..<3).allSatisfy { vertex.position[$0].isFinite && vertex.normal[$0].isFinite }
                })
            else { throw invalid() }
        } else {
            guard joints.allSatisfy({ $0.head == $0.tail }) else { throw invalid() }
        }
        let selected = joints.firstIndex { Data($0.name.utf8) == Data(selectedBoneName.utf8) }
        var vertices: [MeshVertex] = []
        for (index, vertex) in (skeleton?.vertices ?? []).enumerated() {
            if index.isMultiple(of: 1024) { try Task.checkCancellation() }
            var color: SIMD4<Float>
            switch vertex.role {
            case .bone: color = boneColor
            case .selectedBone: color = selectedBoneColor
            case .ring: color = ringColor
            }
            color.w = 1
            vertices.append(MeshVertex(position: vertex.position, normal: vertex.normal, color: color))
        }
        for (index, vertex) in mesh.vertices.enumerated() {
            if index.isMultiple(of: 1024) { try Task.checkCancellation() }
            var weight: Float = 0
            if let selected {
                for slot in 0..<4 where influences[index].joints[slot] == UInt32(selected) {
                    weight += influences[index].weights[slot]
                }
            }
            let color = weight > 0 ? SIMD4(weight, 0, 1 - weight, 0.8) : SIMD4<Float>(0.5, 0.5, 0.5, 0.8)
            vertices.append(MeshVertex(position: vertex.position, normal: vertex.normal, color: color))
        }
        try Task.checkCancellation()
        return Mesh(vertices: vertices, nodeCount: mesh.nodeCount, partCount: mesh.partCount, warning: mesh.warning)
    }
}
