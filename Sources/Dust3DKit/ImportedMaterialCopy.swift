import Dust3DEngine
import Foundation

struct ImportedCopyBudget {
    let maximum: Int
    private(set) var used = 0

    mutating func charge(_ count: Int, width: Int = 1) throws {
        guard count >= 0, width > 0 else { throw ImportedMaterialError.invalidNativeCounts }
        guard count <= (maximum - used) / width else { throw ImportedMaterialError.copyLimitExceeded }
        used += count * width
    }
}

enum ImportedMaterialCopy {
    static func identity(_ pointer: UnsafePointer<CChar>?, budget: inout ImportedCopyBudget) throws -> String {
        let value: String
        do { value = try MeshSourceCopy.identifier(pointer) } catch { throw ImportedMaterialError.invalidIdentity }
        try budget.charge(value.utf8.count + 1)
        return value
    }

    static func sampler(_ value: Dust3DImportedMaterialView) throws -> ImportedTextureSampler? {
        let flags = [value.has_sampler, value.has_magnification_filter, value.has_minification_filter]
        guard flags.allSatisfy({ $0 == 0 || $0 == 1 }) else { throw ImportedMaterialError.invalidSampler }
        guard value.has_sampler == 1 else {
            guard flags.allSatisfy({ $0 == 0 }), value.magnification_filter == 0, value.minification_filter == 0,
                value.wrap_s == 0, value.wrap_t == 0
            else { throw ImportedMaterialError.invalidSampler }
            return nil
        }
        guard let wrapS = ImportedTextureWrapMode(rawValue: value.wrap_s),
            let wrapT = ImportedTextureWrapMode(rawValue: value.wrap_t)
        else { throw ImportedMaterialError.invalidSampler }
        let magnification = ImportedMagnificationFilter(rawValue: value.magnification_filter)
        let minification = ImportedMinificationFilter(rawValue: value.minification_filter)
        guard value.has_magnification_filter == 1 ? magnification != nil : value.magnification_filter == 0,
            value.has_minification_filter == 1 ? minification != nil : value.minification_filter == 0
        else { throw ImportedMaterialError.invalidSampler }
        return ImportedTextureSampler(
            magnification: magnification, minification: minification, wrapS: wrapS, wrapT: wrapT)
    }

    static func image(_ view: Dust3DImportedEncodedImageView, budget: inout ImportedCopyBudget) throws
        -> ImportedEncodedImage?
    {
        guard let mime = view.mime_type else {
            guard view.bytes == nil, view.byte_count == 0 else { throw ImportedMaterialError.invalidImage }
            return nil
        }
        let declaration: String
        do { declaration = try MeshSourceCopy.identifier(mime) } catch { throw ImportedMaterialError.invalidImage }
        guard let encoding = ImportedImageEncoding(rawValue: declaration), let bytes = view.bytes,
            (1...(16 * 1024 * 1024)).contains(view.byte_count)
        else { throw ImportedMaterialError.invalidImage }
        try budget.charge(view.byte_count)
        return ImportedEncodedImage(encoding: encoding, bytes: Data(bytes: bytes, count: view.byte_count))
    }

    static func material(_ view: Dust3DImportedMaterialView, budget: inout ImportedCopyBudget) throws
        -> ImportedModelMaterial
    {
        let id = try identity(view.model_id, budget: &budget)
        let baseColor = SIMD4(view.base_color.0, view.base_color.1, view.base_color.2, view.base_color.3)
        let emissive = SIMD3(view.emissive.0, view.emissive.1, view.emissive.2)
        guard (0..<4).allSatisfy({ baseColor[$0].isFinite && (0...1).contains(baseColor[$0]) }),
            [view.metallic, view.roughness].allSatisfy({ $0.isFinite && (0...1).contains($0) }),
            (0..<3).allSatisfy({ emissive[$0].isFinite && (0...1).contains(emissive[$0]) }),
            view.alpha_cutoff.isFinite, view.alpha_cutoff >= 0, view.is_double_sided == 0 || view.is_double_sided == 1
        else { throw ImportedMaterialError.invalidMaterial }
        let alphaMode: ImportedAlphaMode
        switch view.alpha_mode {
        case DUST3D_IMPORTED_ALPHA_OPAQUE: alphaMode = .opaque
        case DUST3D_IMPORTED_ALPHA_MASK: alphaMode = .mask
        case DUST3D_IMPORTED_ALPHA_BLEND: alphaMode = .blend
        default: throw ImportedMaterialError.invalidMaterial
        }
        let sampler = try sampler(view)
        let image = try image(view.image, budget: &budget)
        guard (sampler == nil) == (image == nil) else { throw ImportedMaterialError.invalidImage }
        return ImportedModelMaterial(
            id: id, baseColor: baseColor, metallic: view.metallic, roughness: view.roughness,
            emissive: emissive, alphaMode: alphaMode, alphaCutoff: view.alpha_cutoff,
            isDoubleSided: view.is_double_sided == 1, sampler: sampler, image: image)
    }

    static func validateCounts(models: Int, bindings: Int, payload: Int, nativeMaximum: Int) throws {
        guard models >= 0, bindings >= 0, payload > 0, payload <= nativeMaximum else {
            throw ImportedMaterialError.invalidNativeCounts
        }
        var remaining = payload
        for (count, width) in [
            (models, MemoryLayout<Dust3DImportedMaterialView>.stride),
            (bindings, MemoryLayout<Dust3DImportedBindingView>.stride),
        ] {
            guard count <= remaining / width else { throw ImportedMaterialError.invalidNativeCounts }
            remaining -= count * width
        }
    }

    static func validateBindings(_ bindings: [ImportedMaterialBinding]) throws {
        var components: Set<[UInt8]> = []
        var partModels: [[UInt8]: [UInt8]] = [:]
        var instanced: Set<[UInt8]> = []
        var uninstanced: Set<[UInt8]> = []
        for binding in bindings {
            let part = Array(binding.partID.utf8)
            let model = Array(binding.modelID.utf8)
            if let previous = partModels[part], previous != model { throw ImportedMaterialError.invalidBinding }
            partModels[part] = model
            if let component = binding.componentID {
                guard !uninstanced.contains(part), components.insert(Array(component.utf8)).inserted else {
                    throw ImportedMaterialError.invalidBinding
                }
                instanced.insert(part)
            } else {
                guard !instanced.contains(part), uninstanced.insert(part).inserted else {
                    throw ImportedMaterialError.invalidBinding
                }
            }
        }
    }

    static func copy(_ owner: OpaquePointer, options: ImportedMaterialOptions) throws -> ImportedMaterials {
        try Task.checkCancellation()
        let modelCount = dust3d_imported_assets_model_count(owner)
        let bindingCount = dust3d_imported_assets_binding_count(owner)
        let nativeBytes = dust3d_imported_assets_payload_bytes(owner)
        try validateCounts(
            models: modelCount, bindings: bindingCount, payload: nativeBytes,
            nativeMaximum: options.maximumNativePayloadBytes == 0
                ? Int(DUST3D_DEFAULT_IMPORTED_ASSET_PAYLOAD_BYTES) : options.maximumNativePayloadBytes)
        var budget = ImportedCopyBudget(maximum: options.maximumCopiedPayloadBytes)
        try budget.charge(1, width: MemoryLayout<ImportedMaterials>.stride)
        try budget.charge(modelCount, width: MemoryLayout<ImportedModelMaterial>.stride)
        try budget.charge(bindingCount, width: MemoryLayout<ImportedMaterialBinding>.stride)
        var models: [ImportedModelMaterial] = []
        models.reserveCapacity(modelCount)
        try budget.charge(models.capacity - modelCount, width: MemoryLayout<ImportedModelMaterial>.stride)
        var modelIDs: Set<[UInt8]> = []
        for index in 0..<modelCount {
            try Task.checkCancellation()
            let value = try material(dust3d_imported_assets_material(owner, index), budget: &budget)
            guard modelIDs.insert(Array(value.id.utf8)).inserted else { throw ImportedMaterialError.invalidIdentity }
            models.append(value)
        }
        var bindings: [ImportedMaterialBinding] = []
        bindings.reserveCapacity(bindingCount)
        try budget.charge(bindings.capacity - bindingCount, width: MemoryLayout<ImportedMaterialBinding>.stride)
        for index in 0..<bindingCount {
            try Task.checkCancellation()
            let view = dust3d_imported_assets_binding(owner, index)
            guard models.indices.contains(view.model_index) else { throw ImportedMaterialError.invalidBinding }
            let part = try identity(view.part_id, budget: &budget)
            let component = try view.component_id.map { try identity($0, budget: &budget) }
            // Model identity shares the immutable Swift string; its record is already charged.
            bindings.append(
                ImportedMaterialBinding(componentID: component, partID: part, modelID: models[view.model_index].id))
        }
        try validateBindings(bindings)
        return ImportedMaterials(
            models: models, bindings: bindings, nativePayloadBytes: nativeBytes, copiedPayloadBytes: budget.used)
    }
}
