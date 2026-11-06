import Foundation

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
