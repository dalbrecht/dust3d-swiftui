import Darwin
import Dust3DDocument
import Dust3DEngine
import Foundation

/// Optional fixed-catalog metadata, independent of document editing and native clip evaluation.
public protocol AnimationCatalogLoading: Sendable {
    /// Copy inherited authoring declarations off the UI actor.
    /// - Returns: Owned immutable identities, controls, common timing and surface names.
    /// - Throws: Original native/copy/cancellation cause; no document is accepted or evaluated.
    func load() async throws -> AnimationAuthoringCatalog
}

/// Host copy boundary over the unchanged reviewed document-free catalog C ABI.
public actor NativeAnimationCatalogLoader: AnimationCatalogLoading {
    private let operation: any AnimationCatalogCopying

    /// Construct without native work. Each load owns/releases its own immutable native catalog.
    /// - Example: `let catalog = try await NativeAnimationCatalogLoader().load()`.
    public init() { operation = NativeAnimationCatalogCopy() }

    init(operation: any AnimationCatalogCopying) { self.operation = operation }

    /// Copy fixed metadata and reject cancelled results before returning to the host.
    /// - Returns: Owned catalog bounded by collection caps and 1 MiB logical copy accounting.
    /// - Throws: Original typed native/copy cause or Swift cancellation before/after copy.
    /// - Note: The quota accounts copied value slots and UTF-8 strings, not allocator overhead,
    ///   temporary validation storage, native catalog construction or RSS. No generation is invoked.
    /// - Example: `try await loader.load()`.
    public func load() async throws -> AnimationAuthoringCatalog {
        try Task.checkCancellation()
        let result = try await operation.copy()
        try Task.checkCancellation()
        return result
    }
}

protocol AnimationCatalogCopying: Sendable {
    func copy() async throws -> AnimationAuthoringCatalog
}

/// One logical retained-copy budget; scalar tests do not allocate or probe foreign memory.
struct AnimationCatalogCopyBudget {
    static let maximumPayloadBytes = 1024 * 1024
    private(set) var remainingBytes: Int

    init(maximumBytes: Int = Self.maximumPayloadBytes) throws {
        guard (1...Self.maximumPayloadBytes).contains(maximumBytes) else { throw AnimationCatalogError.limitExceeded }
        remainingBytes = maximumBytes
    }

    mutating func consume(_ count: Int) throws {
        guard count >= 0, count <= remainingBytes else { throw AnimationCatalogError.limitExceeded }
        remainingBytes -= count
    }

    mutating func consumeRecords(count: Int, stride: Int) throws {
        guard count >= 0, stride >= 0 else { throw AnimationCatalogError.limitExceeded }
        let bytes = count.multipliedReportingOverflow(by: stride)
        guard !bytes.overflow else { throw AnimationCatalogError.limitExceeded }
        try consume(bytes.partialValue)
    }
}

/// Foreign owners/pointers never escape this call, which has no suspension point after construction.
private struct NativeAnimationCatalogCopy: AnimationCatalogCopying {
    func copy() async throws -> AnimationAuthoringCatalog { try copySynchronously() }

    private func copySynchronously() throws -> AnimationAuthoringCatalog {
        var error = Dust3DError()
        guard let owner = dust3d_animation_catalog_load(&error) else { throw MeshLoader.loadingError(error) }
        defer { dust3d_animation_catalog_destroy(owner) }
        guard error.status == DUST3D_STATUS_OK else { throw MeshLoader.loadingError(error) }
        var budget = try AnimationCatalogCopyBudget()
        try budget.consume(MemoryLayout<AnimationAuthoringCatalog>.stride)
        let count = dust3d_animation_catalog_clip_count(owner)
        try validateCount(count, maximum: AnimationAuthoringCatalog.maximumClipCount)
        try budget.consumeRecords(count: count, stride: MemoryLayout<AnimationClipDefinition>.stride)
        var clips: [AnimationClipDefinition] = []
        clips.reserveCapacity(count)
        for index in 0..<count { clips.append(try copyClip(owner, at: index, budget: &budget)) }
        let materialCount = dust3d_animation_catalog_surface_material_count(owner)
        try validateCount(materialCount, maximum: AnimationAuthoringCatalog.maximumSurfaceCount)
        try budget.consumeRecords(count: materialCount, stride: MemoryLayout<String>.stride)
        var materials: [String] = []
        materials.reserveCapacity(materialCount)
        for index in 0..<materialCount {
            materials.append(
                try copyString(dust3d_animation_catalog_surface_material_name(owner, index), budget: &budget))
        }
        var timing = Dust3DAnimationTimingDefinition()
        guard dust3d_animation_timing_definition(&timing) == 1 else { throw AnimationCatalogError.invalidDefinition }
        return try AnimationAuthoringCatalog(
            clips: clips, surfaceMaterials: materials,
            timing: AnimationTimingDefinition(
                minimumSeconds: timing.minimum_duration_seconds, maximumSeconds: timing.maximum_duration_seconds,
                decimalPlaces: Int(timing.duration_decimal_places), secondsStep: timing.duration_step_seconds,
                minimumFrames: Int(timing.minimum_frame_count), maximumFrames: Int(timing.maximum_frame_count),
                framesStep: Int(timing.frame_count_step)))
    }

    private func copyClip(
        _ owner: OpaquePointer, at index: Int, budget: inout AnimationCatalogCopyBudget
    ) throws -> AnimationClipDefinition {
        var info = Dust3DAnimationClipInfo()
        guard dust3d_animation_catalog_clip_at(owner, index, &info) == 1,
            (0...1).contains(info.loops), (0...1).contains(info.is_legacy_alias)
        else { throw AnimationCatalogError.invalidDefinition }
        try validateCount(info.parameter_count, maximum: AnimationClipDefinition.maximumParameterCount)
        try budget.consumeRecords(count: info.parameter_count, stride: MemoryLayout<AnimationParameterDefault>.stride)
        var defaults: [AnimationParameterDefault] = []
        defaults.reserveCapacity(info.parameter_count)
        for parameterIndex in 0..<info.parameter_count {
            var parameter = Dust3DAnimationParameterInfo()
            guard dust3d_animation_catalog_parameter_at(owner, index, parameterIndex, &parameter) == 1 else {
                throw AnimationCatalogError.invalidDefinition
            }
            defaults.append(
                try AnimationParameterDefault(
                    name: copyString(parameter.name, budget: &budget), value: parameter.value))
        }
        let count = dust3d_animation_catalog_control_count(owner, index)
        try validateCount(count, maximum: AnimationClipDefinition.maximumControlCount)
        try budget.consumeRecords(count: count, stride: MemoryLayout<AnimationControlDefinition>.stride)
        var controls: [AnimationControlDefinition] = []
        controls.reserveCapacity(count)
        for controlIndex in 0..<count {
            var control = Dust3DAnimationControlInfo()
            guard dust3d_animation_catalog_control_at(owner, index, controlIndex, &control) == 1 else {
                throw AnimationCatalogError.invalidDefinition
            }
            controls.append(
                try AnimationControlDefinition(
                    name: copyString(control.name, budget: &budget),
                    label: copyString(control.display_name, budget: &budget),
                    minimumSlider: Int(control.minimum_slider_value), maximumSlider: Int(control.maximum_slider_value),
                    defaultSlider: Int(control.default_slider_value), defaultParameter: control.default_parameter_value,
                    divisor: control.slider_divisor, multiplier: control.parameter_multiplier))
        }
        return try AnimationClipDefinition(
            type: copyString(info.type, budget: &budget), rig: copyString(info.rig, budget: &budget),
            generator: copyString(info.generator, budget: &budget), seconds: info.duration_seconds,
            samples: info.sample_count,
            loops: info.loops == 1, isLegacyAlias: info.is_legacy_alias == 1, defaults: defaults, controls: controls)
    }

    private func validateCount(_ count: Int, maximum: Int) throws {
        guard (0...maximum).contains(count) else { throw AnimationCatalogError.limitExceeded }
    }

    private func copyString(_ pointer: UnsafePointer<CChar>?, budget: inout AnimationCatalogCopyBudget) throws -> String
    {
        guard let pointer else { throw AnimationCatalogError.invalidDefinition }
        // The canonical owner guarantees a valid NUL-terminated string; bound the host copy before allocation.
        let count = strnlen(pointer, 1025)
        guard (1...1024).contains(count) else { throw AnimationCatalogError.invalidDefinition }
        try budget.consume(count + 1)
        guard let text = String(validatingCString: pointer) else { throw AnimationCatalogError.invalidDefinition }
        return text
    }
}
