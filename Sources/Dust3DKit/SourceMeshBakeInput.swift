import Dust3DEngine
import Foundation

enum SourceMeshBakeInput {
    static func validate(dataCount: Int, options: SourceMeshBakeOptions) throws {
        let maximum = 256 * 1024 * 1024
        guard dataCount >= 0,
            [
                options.maximumSamplerPayloadBytes, options.maximumAtlasPayloadBytes,
                options.maximumNativePayloadBytes,
            ].allSatisfy({ (0...maximum).contains($0) }),
            (1...maximum).contains(options.maximumCopiedPayloadBytes),
            (1...maximum).contains(options.maximumInputImageBytes),
            (0...100_000).contains(options.maximumChartCount),
            (0...1_000_000_000).contains(options.maximumRasterSamples),
            (0...14).contains(options.maximumMipLevels)
        else { throw SourceMeshBakeError.invalidLimits }
        try MeshBakedInput.validate(dataCount: dataCount, options: options.bake)
    }

    static func validateImages(_ models: [SourceMeshBakeImage], legacy: [MeshBakeImage], maximumBytes: Int) throws {
        guard models.count <= 10000, legacy.count <= 10000 else { throw SourceMeshBakeError.invalidInputImage }
        var remaining = maximumBytes
        // Bound actual caller storage, including padding, before any NSData bridging.
        for count in models.map({ $0.pixels.count }) + legacy.map({ $0.pixels.count }) {
            guard count <= remaining else { throw SourceMeshBakeError.inputLimitExceeded }
            remaining -= count
        }
        var keys: Set<[UInt8]> = []
        for image in models {
            try Task.checkCancellation()
            guard (1...128).contains(image.modelID.utf8.count) else { throw SourceMeshBakeError.invalidInputImage }
            let key = Array(image.modelID.utf8)
            guard (1...128).contains(key.count), !key.contains(0), keys.insert(key).inserted,
                (1...8192).contains(image.width), (1...8192).contains(image.height)
            else { throw SourceMeshBakeError.invalidInputImage }
            let rowBytes = image.width * 4
            guard image.rowStride >= rowBytes, image.pixels.count >= rowBytes,
                image.height == 1 || image.rowStride <= (image.pixels.count - rowBytes) / (image.height - 1)
            else { throw SourceMeshBakeError.invalidInputImage }
        }
    }

    static func native(_ options: SourceMeshBakeOptions, cancellation: OpaquePointer?) -> Dust3DSourceBakeOptions {
        var value = Dust3DSourceBakeOptions()
        value.struct_size = MemoryLayout<Dust3DSourceBakeOptions>.size
        value.legacy.struct_size = MemoryLayout<Dust3DBakeOptions>.size
        value.legacy.color_size = options.bake.colorSize
        value.legacy.normal_size = options.bake.normalSize
        value.legacy.material_size = options.bake.materialSize
        value.legacy.atlas_texture_size = options.bake.atlasTextureSize
        value.legacy.maximum_uv_payload_bytes = options.bake.maximumMetadataPayloadBytes
        value.legacy.maximum_bake_payload_bytes = options.bake.maximumBakePayloadBytes
        value.legacy.maximum_spatial_grid_entries = options.bake.maximumSpatialGridEntries
        value.legacy.cancellation = cancellation
        value.maximum_sampler_payload_bytes = options.maximumSamplerPayloadBytes
        value.maximum_atlas_payload_bytes = options.maximumAtlasPayloadBytes
        value.maximum_output_payload_bytes = options.maximumNativePayloadBytes
        value.maximum_chart_count = options.maximumChartCount
        value.maximum_raster_samples = options.maximumRasterSamples
        return value
    }
}
