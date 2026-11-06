import Foundation

extension GeneratedRigSkeleton {
    /// Preserve generated source indices for each triangle, including gaps for
    /// zero-axis joints. Picking metadata never infers identity from color/name.
    package func triangleOwners() throws -> [UInt32] {
        guard !boneNames.isEmpty, boneNames.count <= 256, vertices.count.isMultiple(of: 3) else {
            throw RigTemplateHierarchyError.invalidMetadata("invalid skeleton picking triangle ownership")
        }
        var owners: [UInt32] = []
        owners.reserveCapacity(vertices.count / 3)
        for start in stride(from: 0, to: vertices.count, by: 3) {
            if start.isMultiple(of: 3072) { try Task.checkCancellation() }
            let index = vertices[start].boneIndex
            guard boneNames.indices.contains(index), vertices[start + 1].boneIndex == index,
                vertices[start + 2].boneIndex == index
            else { throw RigTemplateHierarchyError.invalidMetadata("invalid skeleton picking triangle ownership") }
            owners.append(UInt32(index))
        }
        try Task.checkCancellation()
        return owners
    }
}
