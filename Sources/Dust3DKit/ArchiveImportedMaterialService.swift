import Foundation

/// Geometry-only selection, or fully prepared authored inputs for a pure imported surface.
public enum ArchiveImportedMaterialSelection: Sendable {
    case procedural
    case mixed
    case imported(ImportedMaterialRenderData)
}

/// Optional imported preparation boundary, substitutable in scene revision/cancellation tests.
public protocol ArchiveImportedMaterialLoading: Sendable {
    /// Prepare one exact archive snapshot, returning nil for geometry without imported surface models.
    /// - Parameters: data is immutable complete archive bytes; limits bound retained outputs.
    /// - Returns: Independent source/material/image values, or nil for the existing procedural bake path.
    /// - Throws: Original native/codec failures, ImportedMaterialRenderError or CancellationError.
    func loadIfPresent(data: Data, limits: ImportedMaterialRenderLimits) async throws -> ImportedMaterialRenderData?

    /// Select without decoding mixed images; selected bakers enforce their own image policy.
    /// - Parameters: data is exact archive bytes; limits apply only to pure imported preparation;
    ///   inspectionLimits independently bound temporary geometry used for selection.
    /// - Returns: A data-free procedural/mixed choice, or owned pure imported rendering inputs.
    /// - Throws: Original inspection/preparation failure or cancellation.
    func selectForPreparation(
        data: Data, limits: ImportedMaterialRenderLimits, inspectionLimits: ImportedSurfaceOptions
    ) async throws -> ArchiveImportedMaterialSelection
}

extension ArchiveImportedMaterialLoading {
    /// Adapt existing injected loaders; production overrides this with image-free geometry inspection.
    /// - Parameters: data, limits and inspectionLimits have the protocol's ownership contracts.
    /// - Returns: A selection derived from the injected prepared surface.
    /// - Throws: Original injected loader error or cancellation.
    public func selectForPreparation(
        data: Data, limits: ImportedMaterialRenderLimits, inspectionLimits: ImportedSurfaceOptions
    ) async throws -> ArchiveImportedMaterialSelection {
        guard let imported = try await loadIfPresent(data: data, limits: limits) else { return .procedural }
        try Task.checkCancellation()
        if imported.surface.triangles.contains(where: { $0.modelIndex == nil }) { return .mixed }
        return .imported(imported)
    }
}

/// Serialized background preparation with no retained native pointer or observable state.
public actor ArchiveImportedMaterialService: ArchiveImportedMaterialLoading {
    public init() {}

    /// Inspect owned geometry before selecting image admission, without copying material images.
    /// - Parameters: data is unchanged archive bytes; limits apply to pure imported output;
    ///   inspectionLimits bound the separate temporary source-geometry owner.
    /// - Returns: Data-free mixed/procedural choice or fully prepared imported inputs.
    /// - Throws: Original geometry/preparation error or cancellation.
    public func selectForPreparation(
        data: Data, limits: ImportedMaterialRenderLimits, inspectionLimits: ImportedSurfaceOptions
    ) async throws -> ArchiveImportedMaterialSelection {
        try Task.checkCancellation()
        let kind = try inspectSurface(data: data, limits: inspectionLimits)
        try Task.checkCancellation()
        guard kind == .imported else { return kind == .mixed ? .mixed : .procedural }
        guard let imported = try await loadIfPresent(data: data, limits: limits) else { return .procedural }
        return .imported(imported)
    }

    private enum SurfaceKind { case procedural, mixed, imported }

    private func inspectSurface(data: Data, limits: ImportedSurfaceOptions) throws -> SurfaceKind {
        let surface = try ImportedSurfaceLoader.load(data: data, options: limits)
        try Task.checkCancellation()
        guard surface.triangles.contains(where: { $0.modelIndex != nil }) else { return .procedural }
        return surface.triangles.contains(where: { $0.modelIndex == nil }) ? .mixed : .imported
    }

    /// Join source facts and decoded images from the same unchanged archive off the main actor.
    /// - Parameters: data is complete archive bytes; limits are independent layered quotas.
    /// - Returns: Immutable coherent inputs; material factors have not been applied to source samples.
    /// - Throws: Original failures or cancellation before/after synchronous preparation.
    /// - Example: try await ArchiveImportedMaterialService().loadIfPresent(data: archive, limits: .init()).
    public func loadIfPresent(data: Data, limits: ImportedMaterialRenderLimits) async throws
        -> ImportedMaterialRenderData?
    {
        try Task.checkCancellation()
        let value = try ImportedMaterialRenderLoader.loadIfPresent(data: data, limits: limits)
        try Task.checkCancellation()
        return value
    }
}

/// Synchronous ownership boundary; call off the main actor.
public enum ImportedMaterialRenderLoader {
    /// Prepare owned model/image inputs without packing UVs or modifying archive bytes.
    /// - Parameters: data is the exact source archive; limits bound each retained-data layer.
    /// - Returns: Data aligned with the source model catalog, or nil when no imported model is rendered.
    /// - Throws: Original native/codec errors, typed join/quota errors or CancellationError.
    /// - Example: let inputs = try ImportedMaterialRenderLoader.loadIfPresent(data: archive, limits: .init()).
    public static func loadIfPresent(data: Data, limits: ImportedMaterialRenderLimits = .init()) throws
        -> ImportedMaterialRenderData?
    {
        try Task.checkCancellation()
        try validate(dataCount: data.count, limits: limits)
        let facts = try ImportedMaterialLoader.load(data: data, options: limits.materials)
        try Task.checkCancellation()
        guard !facts.models.isEmpty else { return nil }
        let surface = try ImportedSurfaceLoader.load(data: data, options: limits.surface)
        try Task.checkCancellation()
        guard surface.triangles.contains(where: { $0.modelIndex != nil }) else { return nil }
        let decoded = try decodeMaterials(facts.models, modelIDs: surface.modelIDs, limits: limits)
        try Task.checkCancellation()
        return ImportedMaterialRenderData(
            surface: surface, materials: decoded.materials, decodedPayloadBytes: decoded.bytes)
    }

    static func validate(dataCount: Int, limits: ImportedMaterialRenderLimits) throws {
        let ceiling = 256 * 1024 * 1024
        guard (1...ceiling).contains(limits.maximumEncodedImageBytes),
            (1...ceiling).contains(limits.maximumDecodedTotalBytes)
        else { throw ImportedMaterialRenderError.invalidLimits }
        try ImportedSurfaceLoader.validate(dataCount: dataCount, options: limits.surface)
        try ImportedMaterialLoader.validate(dataCount: dataCount, options: limits.materials)
    }

    static func decodeMaterials(
        _ definitions: [ImportedModelMaterial], modelIDs: [ImportedSurfaceIdentity],
        limits: ImportedMaterialRenderLimits
    ) throws -> (materials: [ImportedRenderMaterial], bytes: Int) {
        var byIdentity: [ImportedSurfaceIdentity: ImportedModelMaterial] = [:]
        for definition in definitions {
            try Task.checkCancellation()
            let id = try ImportedSurfaceIdentity(rawValue: definition.id)
            guard byIdentity.updateValue(definition, forKey: id) == nil else {
                throw ImportedMaterialRenderError.duplicateMaterial(id.rawValue)
            }
        }
        var used = 0
        var materials: [ImportedRenderMaterial] = []
        materials.reserveCapacity(modelIDs.count)
        for id in modelIDs {
            try Task.checkCancellation()
            guard let definition = byIdentity[id] else {
                throw ImportedMaterialRenderError.missingMaterial(id.rawValue)
            }
            let image: ImportedDecodedImage?
            if let encoded = definition.image {
                let remaining = limits.maximumDecodedTotalBytes - used
                guard remaining > 0 else { throw ImportedMaterialRenderError.decodedLimitExceeded(id.rawValue) }
                image = try ImportedImageDecoder.decode(
                    encoded, modelID: id.rawValue,
                    maximumEncodedBytes: limits.maximumEncodedImageBytes, maximumDecodedBytes: remaining)
                used += image?.pixels.count ?? 0
            } else {
                image = nil
            }
            materials.append(ImportedRenderMaterial(id: id, definition: definition, image: image))
        }
        try Task.checkCancellation()
        return (materials, used)
    }
}
