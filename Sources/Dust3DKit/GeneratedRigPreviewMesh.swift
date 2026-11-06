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

/// Unnormalized skeleton geometry derived from one generated rig's grounded joints.
/// Indices and names retain the full source-joint order, including zero-axis joints.
package struct GeneratedRigSkeleton: Sendable {
    package let vertices: [RigTemplateMeshVertex]
    package let boneNames: [String]
}

#if MOTE3D_EXPERIMENTAL_GENERATED_RIG
    import Dust3DEngine

    extension GeneratedRig {
        /// Build only visualization geometry, never a rig, pose or animation. The caller
        /// schedules this synchronous bounded math off the main actor. Exact zero-axis
        /// joints remain in the source data but have no drawable solid/ring; nil means
        /// every joint has a zero axis. Coordinates remain in the grounded body frame.
        package func skeletonMesh(selectedBoneName: String = "") throws -> GeneratedRigSkeleton? {
            try Task.checkCancellation()
            guard !joints.isEmpty, joints.count <= 256 else { throw Self.skeletonFailure("joint count") }
            func validName(_ name: String, emptyAllowed: Bool) -> Bool {
                (emptyAllowed || !name.isEmpty) && name.utf8.count <= 1024
                    && name.utf8.allSatisfy { $0 >= 32 && $0 != 127 }
            }
            guard validName(selectedBoneName, emptyAllowed: true) else {
                throw Self.skeletonFailure("selected name")
            }
            var names = Set<Data>()
            var originalIndices: [Int] = []
            for (index, joint) in joints.enumerated() {
                try Task.checkCancellation()
                guard validName(joint.name, emptyAllowed: false), names.insert(Data(joint.name.utf8)).inserted,
                    joint.capsuleRadius.isFinite, joint.capsuleRadius >= 0, joint.capsuleRadius <= 1_000_000,
                    (0..<3).allSatisfy({
                        joint.head[$0].isFinite && joint.tail[$0].isFinite
                            && abs(joint.head[$0]) <= 1_000_000 && abs(joint.tail[$0]) <= 1_000_000
                    })
                else { throw Self.skeletonFailure("joint identity/geometry") }
                // A Float length-squared test can underflow for valid tiny axes.
                if (0..<3).contains(where: { joint.head[$0] != joint.tail[$0] }) {
                    originalIndices.append(index)
                }
            }
            guard !originalIndices.isEmpty else { return nil }
            let filteredNames = originalIndices.map { joints[$0].name }
            var nameBytes: [CChar] = []
            var offsets: [Int] = []
            for name in filteredNames {
                offsets.append(nameBytes.count)
                nameBytes.append(contentsOf: name.utf8.map { CChar(bitPattern: $0) })
            }
            let copied = try nameBytes.withUnsafeBufferPointer { names in
                var inputs: [Dust3DRigTemplateBoneInput] = []
                for (filteredIndex, originalIndex) in originalIndices.enumerated() {
                    let joint = joints[originalIndex]
                    var bone = Dust3DRigTemplateBoneInput()
                    bone.name = names.baseAddress?.advanced(by: offsets[filteredIndex])
                    bone.name_length = joint.name.utf8.count
                    bone.from_position = (joint.head.x, joint.head.y, joint.head.z)
                    bone.to_position = (joint.tail.x, joint.tail.y, joint.tail.z)
                    bone.capsule_radius = joint.capsuleRadius
                    inputs.append(bone)
                }
                return try selectedBoneName.utf8CString.withUnsafeBufferPointer { selected in
                    var options = dust3d_rig_template_default_options()
                    options.normalize = 0
                    options.selected_bone_name = selected.baseAddress
                    options.selected_bone_name_length = selected.count - 1
                    var error = Dust3DError()
                    return try inputs.withUnsafeBufferPointer { bones in
                        guard
                            let owner = dust3d_rig_template_mesh_create(
                                bones.baseAddress, bones.count, &options, &error)
                        else { throw MeshLoader.loadingError(error) }
                        defer { dust3d_rig_template_mesh_destroy(owner) }
                        try Task.checkCancellation()
                        return try RigTemplateMesh.copy(owner, expectedNames: filteredNames)
                    }
                }
            }
            var vertices: [RigTemplateMeshVertex] = []
            vertices.reserveCapacity(copied.vertices.count)
            for (index, vertex) in copied.vertices.enumerated() {
                if index.isMultiple(of: 1024) { try Task.checkCancellation() }
                guard originalIndices.indices.contains(vertex.boneIndex) else {
                    throw Self.skeletonFailure("source joint mapping")
                }
                vertices.append(
                    RigTemplateMeshVertex(
                        position: vertex.position, normal: vertex.normal,
                        boneIndex: originalIndices[vertex.boneIndex], role: vertex.role))
            }
            try Task.checkCancellation()
            return GeneratedRigSkeleton(vertices: vertices, boneNames: joints.map(\.name))
        }

        private static func skeletonFailure(_ reason: String) -> MeshLoadingError {
            MeshLoadingError(
                status: UInt32(DUST3D_STATUS_GENERATION_FAILED.rawValue),
                message: "Invalid generated skeleton: \(reason)")
        }
    }
#endif
