import Foundation

#if MOTE3D_EXPERIMENTAL_RIG_TEMPLATE || MOTE3D_EXPERIMENTAL_GENERATED_RIG
    import Dust3DEngine
#endif

/// Semantic roles retain source ownership independently of platform colors.
public enum RigTemplateMeshRole: UInt32, Sendable {
    case bone = 0
    case selectedBone = 1
    case ring = 2
}

/// A copied triangle vertex with a flat normal; consecutive triples form triangles.
/// boneIndex addresses the owning mesh's source-order boneNames. No native buffer escapes.
public struct RigTemplateMeshVertex: Sendable {
    public let position: SIMD3<Float>
    public let normal: SIMD3<Float>
    public let boneIndex: Int
    public let role: RigTemplateMeshRole
}

/// Immutable, template-only geometry. Does not generate a document rig or pose.
public struct RigTemplateMesh: Sendable {
    public let vertices: [RigTemplateMeshVertex]
    public let boneNames: [String]

    #if MOTE3D_EXPERIMENTAL_RIG_TEMPLATE
        /// Read a verified bundled template and copy the portable core visualization.
        /// The synchronous work must be scheduled off the main actor by UI callers.
        /// - Parameters:
        ///   - sourceType: Exact pinned template type; nil, empty or None means no template.
        ///   - selectedBoneName: Exact UTF-8 name whose solid vertices receive the selected role.
        /// - Returns: Independent Swift-owned geometry and names, or nil for no template.
        /// - Throws: Resource/hierarchy errors, CancellationError, or MeshLoadingError retaining
        ///   the native status and diagnostic. No document rig or pose is generated.
        /// - Example: `let preview = try RigTemplateMesh.load(sourceType: "Snake", selectedBoneName: "Root")`.
        public static func load(sourceType: String?, selectedBoneName: String = "") throws -> Self? {
            try Task.checkCancellation()
            guard let data = try RigTemplateResources.data(forSourceType: sourceType), let sourceType else {
                return nil
            }
            return try parse(data, expectedType: sourceType, selectedBoneName: selectedBoneName)
        }

        static func parse(_ data: Data, expectedType: String, selectedBoneName: String = "") throws -> Self {
            try Task.checkCancellation()
            let hierarchy = try RigTemplateHierarchy.parse(data, expectedType: expectedType)
            // Hierarchy parsing has already bounded bytes and forbidden entity declarations.
            let document = try XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever])
            guard let root = document.rootElement() else { throw invalid("missing template root") }
            let elements = root.elements(forName: "bone")
            guard elements.count == hierarchy.bones.count else { throw invalid("inconsistent bone metadata") }
            var nameBytes: [CChar] = []
            var offsets: [Int] = []
            for bone in hierarchy.bones {
                offsets.append(nameBytes.count)
                nameBytes.append(contentsOf: bone.name.utf8.map { CChar(bitPattern: $0) })
            }
            return try nameBytes.withUnsafeBufferPointer { names in
                var inputs: [Dust3DRigTemplateBoneInput] = []
                for (index, element) in elements.enumerated() {
                    var bone = Dust3DRigTemplateBoneInput()
                    bone.name = names.baseAddress?.advanced(by: offsets[index])
                    bone.name_length = hierarchy.bones[index].name.utf8.count
                    bone.from_position = try position(element, child: "position")
                    bone.to_position = try position(element, child: "endPosition")
                    // The reference XML loader leaves capsuleRadius at zero.
                    inputs.append(bone)
                }
                return try selectedBoneName.utf8CString.withUnsafeBufferPointer { selected in
                    var options = dust3d_rig_template_default_options()
                    options.selected_bone_name = selected.baseAddress
                    options.selected_bone_name_length = selected.count - 1
                    var error = Dust3DError()
                    return try inputs.withUnsafeBufferPointer { bones in
                        guard
                            let owner = dust3d_rig_template_mesh_create(
                                bones.baseAddress, bones.count, &options, &error)
                        else {
                            throw MeshLoader.loadingError(error)
                        }
                        defer { dust3d_rig_template_mesh_destroy(owner) }
                        try Task.checkCancellation()
                        return try copy(owner, expectedNames: hierarchy.bones.map(\.name))
                    }
                }
            }
        }

    #endif

    /// Copy role-colored draw records for the renderer using a platform-supplied palette.
    /// No platform colors enter the core. The preview schedules this copy on its worker.
    /// - Parameters:
    ///   - boneColor: Finite RGBA value for ordinary bone solids.
    ///   - selectedBoneColor: Finite RGBA value for selected bone solids.
    ///   - ringColor: Finite RGBA value for all capsule rings, including the selected bone's ring.
    /// - Returns: An independent Mesh preserving positions, normals and triangle order.
    /// - Throws: RigTemplateHierarchyError for non-finite colors, or CancellationError.
    /// - Example: `let mesh = try template.displayMesh(boneColor: .one, selectedBoneColor: .one, ringColor: .one)`.
    public func displayMesh(boneColor: SIMD4<Float>, selectedBoneColor: SIMD4<Float>, ringColor: SIMD4<Float>)
        throws -> Mesh
    {
        guard
            [boneColor, selectedBoneColor, ringColor].allSatisfy({ color in
                (0..<4).allSatisfy { color[$0].isFinite }
            })
        else { throw Self.invalid("non-finite template display color") }
        var copied: [MeshVertex] = []
        copied.reserveCapacity(vertices.count)
        for (index, vertex) in vertices.enumerated() {
            if index.isMultiple(of: 1024) { try Task.checkCancellation() }
            let color: SIMD4<Float>
            switch vertex.role {
            case .bone: color = boneColor
            case .selectedBone: color = selectedBoneColor
            case .ring: color = ringColor
            }
            copied.append(MeshVertex(position: vertex.position, normal: vertex.normal, color: color))
        }
        try Task.checkCancellation()
        return Mesh(vertices: copied, nodeCount: 0, partCount: 0, warning: "")
    }

    #if MOTE3D_EXPERIMENTAL_RIG_TEMPLATE
        private static func position(_ element: XMLElement, child: String) throws -> (Float, Float, Float) {
            let children = element.elements(forName: child)
            guard children.count == 1 else { throw invalid("missing or duplicate \(child)") }
            func coordinate(_ key: String) throws -> Float {
                guard let text = children[0].attribute(forName: key)?.stringValue,
                    let value = Float(text), value.isFinite, abs(value) <= 1_000_000
                else { throw invalid("invalid \(child) \(key)") }
                return value
            }
            return try (coordinate("x"), coordinate("y"), coordinate("z"))
        }

    #endif

    #if MOTE3D_EXPERIMENTAL_RIG_TEMPLATE || MOTE3D_EXPERIMENTAL_GENERATED_RIG
        static func copy(_ owner: OpaquePointer, expectedNames: [String]) throws -> Self {
            let count = dust3d_rig_template_mesh_vertex_count(owner)
            let boneCount = dust3d_rig_template_mesh_bone_count(owner)
            let payload = dust3d_rig_template_mesh_output_bytes(owner)
            guard count > 0, count <= 500_000, count.isMultiple(of: 3), boneCount == expectedNames.count,
                boneCount > 0, boneCount <= 256, payload <= 32 * 1024 * 1024,
                count <= payload / MemoryLayout<Dust3DRigTemplateDrawVertex>.stride,
                let draw = dust3d_rig_template_mesh_vertices(owner)
            else { throw invalid("invalid native draw counts") }
            var names: [String] = []
            var charged = count * MemoryLayout<Dust3DRigTemplateDrawVertex>.stride
            for index in 0..<boneCount {
                var bytes = 0
                guard let pointer = dust3d_rig_template_mesh_bone_name(owner, index, &bytes),
                    bytes > 0, bytes <= 1024,
                    let name = String(bytes: UnsafeRawBufferPointer(start: pointer, count: bytes), encoding: .utf8),
                    Data(name.utf8) == Data(expectedNames[index].utf8)
                else { throw invalid("invalid native source name") }
                charged += bytes + 1
                names.append(name)
            }
            guard charged == payload else { throw invalid("inconsistent native retained payload") }
            var copied: [RigTemplateMeshVertex] = []
            copied.reserveCapacity(count)
            for index in 0..<count {
                if index.isMultiple(of: 1024) { try Task.checkCancellation() }
                let value = draw[index]
                let position = SIMD3(value.position.0, value.position.1, value.position.2)
                let normal = SIMD3(value.normal.0, value.normal.1, value.normal.2)
                guard Int(value.bone_index) < boneCount, let role = RigTemplateMeshRole(rawValue: value.role),
                    (0..<3).allSatisfy({ position[$0].isFinite && normal[$0].isFinite })
                else { throw invalid("invalid native draw record") }
                copied.append(
                    RigTemplateMeshVertex(
                        position: position, normal: normal, boneIndex: Int(value.bone_index), role: role))
            }
            try Task.checkCancellation()
            return Self(vertices: copied, boneNames: names)
        }

    #endif

    private static func invalid(_ reason: String) -> RigTemplateHierarchyError { .invalidMetadata(reason) }
}
