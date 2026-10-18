import CoreGraphics
import Dust3DKit
import Foundation
import Metal

/// Read-only image rendering through the same material encoder as native app viewports.
public enum FilePreviewRenderer {
    private static let builder = TexturedMetalResourcesBuilder()
    private static let imageConverter = FilePreviewImageConverter()

    /// Render a fitted object on a transparent background without creating a window.
    /// - Parameters:
    ///   - bakedMesh: Owned geometry and matching maps from the archive baking service.
    ///   - maximumSize: Requested point dimensions; output preserves aspect within 2048 pixels per side.
    ///   - scale: Requested display scale, positive and at most eight.
    /// - Returns: Owned sRGB image with correctly premultiplied alpha for system previews.
    /// - Throws: `FilePreviewError`, original material/Metal errors or `CancellationError`.
    /// - Note: Geometry/maps have a combined 64 MiB logical quota. Offscreen attachments,
    ///   readback, CPU source/workspace and driver overhead are additional, not a hard RSS cap.
    @MainActor
    public static func render(
        bakedMesh: MeshWithBakedTextures, maximumSize: CGSize, scale: CGFloat
    ) async throws -> FilePreviewImage {
        try Task.checkCancellation()
        let dimensions = try FilePreviewDimensions(maximumSize: maximumSize, scale: scale)
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw FilePreviewError.unavailable("This Mac does not provide a Metal device for file previews.")
        }
        let owner = try await builder.make(
            bakedMesh: bakedMesh, device: device, camera: OrbitCamera(yaw: -0.4, pitch: 0.2, distance: 3),
            maximumPayloadBytes: 64 * 1024 * 1024)
        try Task.checkCancellation()
        let renderer = TexturedMeshRenderer(resources: owner)
        let (pixels, stride) = try await readPixels(
            device: device, dimensions: dimensions, pixelFormat: .bgra8Unorm_srgb
        ) { encoder, size in renderer.encode(encoder: encoder, drawableSize: size) }
        try Task.checkCancellation()
        return try await imageConverter.convert(pixels, dimensions: dimensions, sourceRowStride: stride)
    }

    /// Render ordinary geometry when optional materials are unavailable.
    /// - Parameters:
    ///   - mesh: Copied indexed geometry with source vertex colors.
    ///   - maximumSize: Maximum point dimensions, bounded to 2048 output pixels per side.
    ///   - scale: Positive display scale, at most eight.
    /// - Returns: Owned sRGB image; geometry remains opaque when material alpha is unavailable.
    /// - Throws: `FilePreviewError`, original renderer errors or `CancellationError`.
    @MainActor
    public static func render(mesh: IndexedMesh, maximumSize: CGSize, scale: CGFloat) async throws -> FilePreviewImage {
        try Task.checkCancellation()
        let dimensions = try FilePreviewDimensions(maximumSize: maximumSize, scale: scale)
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw FilePreviewError.unavailable("This Mac does not provide a Metal device for file previews.")
        }
        let geometry = try await imageConverter.prepare(mesh)
        try Task.checkCancellation()
        // The legacy ordinary GPU setup remains a thin main-actor boundary; CPU preparation is background work.
        let renderer = try MeshRenderer(geometry: geometry, device: device)
        renderer.camera = OrbitCamera(yaw: -0.4, pitch: 0.2, distance: 3)
        let (pixels, stride) = try await readPixels(
            device: device, dimensions: dimensions, pixelFormat: .bgra8Unorm
        ) { encoder, size in renderer.encode(encoder: encoder, drawableSize: size) }
        try Task.checkCancellation()
        return try await imageConverter.convert(
            pixels, dimensions: dimensions, sourceRowStride: stride, isSRGBRenderTarget: false)
    }

    @MainActor
    private static func readPixels(
        device: any MTLDevice, dimensions: FilePreviewDimensions, pixelFormat: MTLPixelFormat,
        encode: @MainActor (any MTLRenderCommandEncoder, CGSize) -> Void
    ) async throws -> (Data, Int) {
        // Texture-to-buffer blits require aligned rows; packed output is produced off the UI actor.
        let stride = ((dimensions.rowStride + 255) / 256) * 256
        let count = stride * dimensions.pixelHeight
        guard count <= device.maxBufferLength else {
            throw FilePreviewError.unavailable("The file preview readback exceeds this Metal device's buffer limit.")
        }
        let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat, width: dimensions.pixelWidth, height: dimensions.pixelHeight,
            mipmapped: false)
        colorDescriptor.usage = .renderTarget
        colorDescriptor.storageMode = .private
        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float, width: dimensions.pixelWidth, height: dimensions.pixelHeight, mipmapped: false)
        depthDescriptor.usage = .renderTarget
        depthDescriptor.storageMode = .private
        guard let color = device.makeTexture(descriptor: colorDescriptor),
            let depth = device.makeTexture(descriptor: depthDescriptor),
            let destination = device.makeBuffer(length: count, options: .storageModeShared),
            let queue = device.makeCommandQueue(), let command = queue.makeCommandBuffer()
        else { throw FilePreviewError.unavailable("Metal could not allocate the file preview render targets.") }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = color
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            throw FilePreviewError.unavailable("Metal could not begin the file preview render pass.")
        }
        encode(encoder, CGSize(width: dimensions.pixelWidth, height: dimensions.pixelHeight))
        encoder.endEncoding()
        guard let blit = command.makeBlitCommandEncoder() else {
            throw FilePreviewError.unavailable("Metal could not begin file preview readback.")
        }
        blit.copy(
            from: color, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: dimensions.pixelWidth, height: dimensions.pixelHeight, depth: 1),
            to: destination, destinationOffset: 0, destinationBytesPerRow: stride, destinationBytesPerImage: count)
        blit.endEncoding()
        // Keep all resource owners alive until GPU completion, including when the caller cancels.
        await withCheckedContinuation { continuation in
            command.addCompletedHandler { _ in continuation.resume() }
            command.commit()
        }
        if let error = command.error { throw error }
        guard command.status == .completed else {
            throw FilePreviewError.unavailable("Metal did not complete the file preview render pass.")
        }
        try Task.checkCancellation()
        return (Data(bytes: destination.contents(), count: count), stride)
    }
}

/// Potentially large per-pixel color conversion stays away from the UI executor.
private actor FilePreviewImageConverter {
    func prepare(_ mesh: IndexedMesh) throws -> RenderGeometry {
        try Task.checkCancellation()
        let budget = 64 * 1024 * 1024
        let stride = MemoryLayout<RenderGeometry.Vertex>.stride
        guard mesh.vertices.count <= budget / stride,
            mesh.indices.count <= (budget - mesh.vertices.count * stride) / MemoryLayout<UInt32>.stride
        else { throw FilePreviewError.unavailable("The ordinary file preview exceeds its 64 MiB geometry quota.") }
        return try RenderGeometry(mesh: .indexed(mesh))
    }

    func convert(
        _ pixels: Data, dimensions: FilePreviewDimensions, sourceRowStride: Int, isSRGBRenderTarget: Bool = true
    ) throws -> FilePreviewImage {
        try FilePreviewImage(
            gpuPixels: pixels, dimensions: dimensions, isSRGBRenderTarget: isSRGBRenderTarget,
            sourceRowStride: sourceRowStride)
    }
}
