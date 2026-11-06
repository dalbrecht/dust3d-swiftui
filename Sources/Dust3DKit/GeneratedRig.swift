import Foundation

/// Four original influences, copied into admitted mesh draw-corner order.
/// Unused slots have joint UInt32.max and weight0; no root weight is invented.
public struct GeneratedRigInfluences: Sendable {
    public let joints: SIMD4<UInt32>
    public let weights: SIMD4<Float>
    public var isBound: Bool { weights.x > 0 || weights.y > 0 || weights.z > 0 || weights.w > 0 }
}

/// Final grounded bone values; matrices are16 column-major doubles acting on columns.
public struct GeneratedRigJoint: Sendable {
    public let name: String
    public let parentIndex: Int?
    public let head: SIMD3<Float>
    public let tail: SIMD3<Float>
    public let capsuleRadius: Float
    public let closingAngle: Float
    public let restWorld: [Double]
    public let inverseBind: [Double]
}

/// Independent immutable actual rig and grounded mesh. No native handle survives loading.
/// This is rest data, not a pose/animation result or complete UV/export material model.
public struct GeneratedRig: Sendable {
    public let mesh: Mesh
    public let joints: [GeneratedRigJoint]
    public let influences: [GeneratedRigInfluences]
    public let eyelidsGenerated: Bool
}

#if MOTE3D_EXPERIMENTAL_GENERATED_RIG
    import Dust3DEngine

    /// Background actual-rig loading against a compatible experimental local core.
    /// Cancellation polls native binding/copy phases; other stages have no fixed latency.
    public actor GeneratedRigService {
        public init() {}

        /// Load a pinned template against procedural document bytes off the main actor.
        /// None returns nil; original resource/native errors are preserved. All buffers
        /// are checked/copied before owner destruction. Production core pin is unchanged.
        public func load(data: Data, sourceType: String?, headHasEyelids: Bool = false) async throws -> GeneratedRig? {
            try Task.checkCancellation()
            guard let hierarchy = try RigTemplateHierarchy.load(sourceType: sourceType) else { return nil }
            var error = Dust3DError()
            guard let pointer = dust3d_cancellation_token_create(&error) else { throw MeshLoader.loadingError(error) }
            let token = NativeBakeCancellation(pointer)
            defer { token.close() }
            return try await withTaskCancellationHandler {
                let result = try GeneratedRig.load(
                    data: data, hierarchy: hierarchy, headHasEyelids: headHasEyelids, cancellation: pointer)
                try Task.checkCancellation()
                return result
            } onCancel: {
                token.cancel()
            }
        }
    }

    extension GeneratedRig {
        static func load(
            data: Data, hierarchy: RigTemplateHierarchy, headHasEyelids: Bool = false,
            cancellation: OpaquePointer? = nil
        ) throws -> Self {
            try Task.checkCancellation()
            var bytes: [CChar] = []
            var offsets: [(Int, Int)] = []
            for bone in hierarchy.bones {
                let name = bytes.count
                bytes.append(contentsOf: bone.name.utf8.map { CChar(bitPattern: $0) })
                let parent = bytes.count
                bytes.append(contentsOf: bone.parentName.utf8.map { CChar(bitPattern: $0) })
                offsets.append((name, parent))
            }
            return try bytes.withUnsafeBufferPointer { names in
                var inputs: [Dust3DGeneratedRigBoneInput] = []
                for (index, bone) in hierarchy.bones.enumerated() {
                    var input = Dust3DGeneratedRigBoneInput()
                    input.name = names.baseAddress?.advanced(by: offsets[index].0)
                    input.name_length = bone.name.utf8.count
                    input.parent = names.baseAddress?.advanced(by: offsets[index].1)
                    input.parent_length = bone.parentName.utf8.count
                    inputs.append(input)
                }
                return try hierarchy.type.utf8CString.withUnsafeBufferPointer { type in
                    try inputs.withUnsafeBufferPointer { bones in
                        try data.withUnsafeBytes { archive in
                            var options = dust3d_generated_rig_default_options()
                            options.head_has_eyelids = headHasEyelids ? 1 : 0
                            options.cancellation = cancellation
                            var error = Dust3DError()
                            guard
                                let owner = dust3d_generated_rig_load(
                                    archive.bindMemory(to: UInt8.self).baseAddress, archive.count,
                                    type.baseAddress, type.count - 1, bones.baseAddress, bones.count, &options, &error)
                            else {
                                throw MeshLoader.loadingError(error)
                            }
                            defer { dust3d_generated_rig_destroy(owner) }
                            try Task.checkCancellation()
                            return try copy(owner, expectedNames: hierarchy.bones.map(\.name))
                        }
                    }
                }
            }
        }

        private static func invalid(_ reason: String) -> MeshLoadingError {
            MeshLoadingError(
                status: UInt32(DUST3D_STATUS_GENERATION_FAILED.rawValue), message: "Invalid generated rig: \(reason)")
        }

        private static func matrix<T>(_ tuple: T) throws -> [Double] {
            try withUnsafeBytes(of: tuple) { bytes in
                guard bytes.count == 16 * MemoryLayout<Double>.stride else { throw invalid("matrix layout") }
                let result = Array(bytes.bindMemory(to: Double.self))
                guard result.allSatisfy(\.isFinite) else { throw invalid("nonfinite matrix") }
                return result
            }
        }

        private static func copy(_ owner: OpaquePointer, expectedNames: [String]) throws -> Self {
            let count = dust3d_generated_rig_joint_count(owner)
            let payload = dust3d_generated_rig_output_bytes(owner)
            let eyelids = dust3d_generated_rig_eyelids_generated(owner)
            guard count > 0, count <= 256, eyelids <= 1,
                count == expectedNames.count + (eyelids == 1 ? 4 : 0), payload > 0, payload <= 64 * 1024 * 1024,
                let source = dust3d_generated_rig_joints(owner), let nativeMesh = dust3d_generated_rig_mesh(owner),
                let sourceWeights = dust3d_generated_rig_weights(owner)
            else { throw invalid("native joint ownership/counts") }
            let vertices = dust3d_mesh_vertex_count(nativeMesh)
            let stride = MemoryLayout<Dust3DVertex>.stride + MemoryLayout<Dust3DGeneratedRigWeights>.stride
            guard vertices > 0, vertices <= 15_000_000, vertices.isMultiple(of: 3), vertices <= payload / stride else {
                throw invalid("native draw counts")
            }
            var charged = vertices * stride + count * MemoryLayout<Dust3DGeneratedRigJoint>.stride
            let expected =
                expectedNames
                + (eyelids == 1 ? ["LeftUpperEyelid", "LeftLowerEyelid", "RightUpperEyelid", "RightLowerEyelid"] : [])
            var joints: [GeneratedRigJoint] = []
            for index in 0..<count {
                try Task.checkCancellation()
                var size = 0
                guard let pointer = dust3d_generated_rig_joint_name(owner, index, &size), size > 0, size <= 1024,
                    let name = String(bytes: UnsafeRawBufferPointer(start: pointer, count: size), encoding: .utf8),
                    Data(name.utf8) == Data(expected[index].utf8)
                else { throw invalid("source-order names") }
                charged += size + 1
                let value = source[index]
                let parent = value.parent_index == UInt32.max ? nil : Int(value.parent_index)
                if let parent { guard parent != index, parent < count else { throw invalid("parent index") } }
                guard value.reserved == 0,
                    value.capsule_radius.isFinite, value.capsule_radius >= 0, value.closing_angle.isFinite
                else { throw invalid("joint metadata") }
                let head = SIMD3(value.head_position.0, value.head_position.1, value.head_position.2)
                let tail = SIMD3(value.tail_position.0, value.tail_position.1, value.tail_position.2)
                guard (0..<3).allSatisfy({ head[$0].isFinite && tail[$0].isFinite }) else {
                    throw invalid("joint coordinates")
                }
                joints.append(
                    GeneratedRigJoint(
                        name: name, parentIndex: parent, head: head, tail: tail, capsuleRadius: value.capsule_radius,
                        closingAngle: value.closing_angle, restWorld: try matrix(value.rest_world),
                        inverseBind: try matrix(value.inverse_bind)))
            }
            guard charged <= payload else { throw invalid("payload accounting") }
            for index in joints.indices {
                var seen: Set<Int> = []
                var cursor: Int? = index
                while let node = cursor {
                    guard seen.insert(node).inserted else { throw invalid("cyclic parents") }
                    cursor = joints[node].parentIndex
                }
            }
            var influences: [GeneratedRigInfluences] = []
            influences.reserveCapacity(vertices)
            for index in 0..<vertices {
                if index.isMultiple(of: 1024) { try Task.checkCancellation() }
                let value = sourceWeights[index]
                let indices = SIMD4(value.joints.0, value.joints.1, value.joints.2, value.joints.3)
                let weights = SIMD4(value.weights.0, value.weights.1, value.weights.2, value.weights.3)
                var total = Double.zero
                for slot in 0..<4 {
                    let weight = weights[slot]
                    guard weight.isFinite, weight >= 0, weight <= 1 else { throw invalid("influence weight") }
                    guard weight == 0 ? indices[slot] == UInt32.max : indices[slot] < UInt32(count) else {
                        throw invalid("influence joint")
                    }
                    total += Double(weight)
                }
                guard total == 0 || abs(total - 1) <= 0.0001 else { throw invalid("unnormalized influences") }
                influences.append(GeneratedRigInfluences(joints: indices, weights: weights))
            }
            let mesh = try MeshLoader.copyNativeMesh(nativeMesh)
            guard
                mesh.vertices.allSatisfy({ vertex in
                    (0..<3).allSatisfy { vertex.position[$0].isFinite && vertex.normal[$0].isFinite }
                        && (0..<4).allSatisfy { vertex.color[$0].isFinite }
                })
            else { throw invalid("draw values") }
            try Task.checkCancellation()
            return Self(mesh: mesh, joints: joints, influences: influences, eyelidsGenerated: eyelids == 1)
        }
    }
#endif
