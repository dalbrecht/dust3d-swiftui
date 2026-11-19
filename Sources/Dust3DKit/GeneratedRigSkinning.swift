import simd

/// Admission failures for the copied rig and its matching pose.
enum GeneratedRigSkinningError: Error, Equatable {
    case poseJointCount
    case influenceCount
    case invalidTransform(joint: Int)
    case invalidInfluence(vertex: Int)
    case invalidVertex(Int)
}

extension GeneratedRig {
    /// Apply a caller-owned rigid pose to the grounded rest mesh for numerical comparison.
    /// Each matrix is sixteen column-major doubles in joint order. The caller provides
    /// world transforms in the rig's grounded model space. This operation preserves
    /// draw-corner order, color and mesh metadata, and changes positions and normals.
    package func referenceSkinnedMesh(modelFromJoint: [[Double]]) throws -> Mesh {
        try Task.checkCancellation()
        guard modelFromJoint.count == joints.count else {
            throw GeneratedRigSkinningError.poseJointCount
        }
        guard influences.count == mesh.vertices.count else {
            throw GeneratedRigSkinningError.influenceCount
        }
        let skinMatrices = try joints.indices.map { index in
            guard let pose = rigidSkinningMatrix(modelFromJoint[index]),
                let inverseBind = rigidSkinningMatrix(joints[index].inverseBind)
            else { throw GeneratedRigSkinningError.invalidTransform(joint: index) }
            return pose * inverseBind
        }
        let vertices = try mesh.vertices.indices.map { index in
            if index.isMultiple(of: 1024) { try Task.checkCancellation() }
            return try referenceSkinVertex(mesh.vertices[index], influences[index], skinMatrices, index: index)
        }
        try Task.checkCancellation()
        return Mesh(
            vertices: vertices, nodeCount: mesh.nodeCount, partCount: mesh.partCount,
            warning: mesh.warning)
    }
}

private func rigidSkinningMatrix(_ components: [Double]) -> simd_double4x4? {
    guard components.count == 16, components.allSatisfy(\.isFinite),
        abs(components[3]) <= 1e-8, abs(components[7]) <= 1e-8, abs(components[11]) <= 1e-8,
        abs(components[15] - 1) <= 1e-8
    else { return nil }
    let x = SIMD3(components[0], components[1], components[2])
    let y = SIMD3(components[4], components[5], components[6])
    let z = SIMD3(components[8], components[9], components[10])
    // The core pose contract admits proper rigid frames. Check the basis before
    // applying the Qt reference's direction-vector transform to normals.
    guard abs(simd_length_squared(x) - 1) <= 1e-6,
        abs(simd_length_squared(y) - 1) <= 1e-6,
        abs(simd_length_squared(z) - 1) <= 1e-6,
        abs(simd_dot(x, y)) <= 1e-6, abs(simd_dot(y, z)) <= 1e-6, abs(simd_dot(x, z)) <= 1e-6,
        abs(simd_dot(simd_cross(x, y), z) - 1) <= 1e-6
    else { return nil }
    return simd_double4x4(
        SIMD4(x, 0), SIMD4(y, 0), SIMD4(z, 0), SIMD4(components[12], components[13], components[14], 1))
}

private func referenceSkinVertex(
    _ vertex: MeshVertex, _ influence: GeneratedRigInfluences, _ matrices: [simd_double4x4],
    index: Int
) throws -> MeshVertex {
    guard isFinite(vertex.position), isFinite(vertex.normal) else {
        throw GeneratedRigSkinningError.invalidVertex(index)
    }
    let position = SIMD4(SIMD3<Double>(vertex.position), 1)
    let normal = SIMD4(SIMD3<Double>(vertex.normal), 0)
    var blendedPosition = SIMD4<Double>.zero
    var blendedNormal = SIMD4<Double>.zero
    var total = Double.zero
    for slot in 0..<4 {
        let weight = Double(influence.weights[slot])
        let joint = influence.joints[slot]
        guard weight.isFinite, weight >= 0, weight <= 1,
            weight == 0 ? joint == UInt32.max : Int(joint) < matrices.count
        else { throw GeneratedRigSkinningError.invalidInfluence(vertex: index) }
        if weight == 0 { continue }
        let matrix = matrices[Int(joint)]
        blendedPosition += (matrix * position) * weight
        blendedNormal += (matrix * normal) * weight
        total += weight
    }
    if total == 0 { return vertex }
    guard abs(total - 1) <= 0.0001 else {
        throw GeneratedRigSkinningError.invalidInfluence(vertex: index)
    }
    let skinnedPosition = SIMD3<Float>(xyz(blendedPosition) / total)
    // Qt's reference weights directions using w=0, preserves their original
    // length, and keeps the original direction for a collapsed blend.
    let restLength = simd_length(xyz(normal))
    let transformedLength = simd_length(xyz(blendedNormal))
    let skinnedNormal =
        restLength >= 1e-6 && transformedLength >= 1e-6
        ? SIMD3<Float>(xyz(blendedNormal) * (restLength / transformedLength))
        : vertex.normal
    guard isFinite(skinnedPosition), isFinite(skinnedNormal) else {
        throw GeneratedRigSkinningError.invalidVertex(index)
    }
    return MeshVertex(position: skinnedPosition, normal: skinnedNormal, color: vertex.color)
}

private func xyz(_ value: SIMD4<Double>) -> SIMD3<Double> {
    SIMD3(value.x, value.y, value.z)
}

private func isFinite(_ value: SIMD3<Float>) -> Bool {
    value.x.isFinite && value.y.isFinite && value.z.isFinite
}
