import CoreGraphics
import Dust3DDocument
import Dust3DEditorModel
import Foundation
import ImageIO
import Metal
import XCTest

@testable import Dust3DEditor
@testable import Dust3DKit
@testable import Dust3DRendering

/// One production-pin Store output, one fixed camera and one same-geometry omitted-normal control.
@MainActor final class ComponentSurfaceNormalRenderingTests: XCTestCase {
    private enum Failure: Error { case timeout, unexpectedMap, incompleteGPU }
    private let size = 512
    private let camera = OrbitCamera(yaw: -0.4, pitch: 0.2, distance: 3)

    private func settle(_ store: EditorStore) async throws {
        for _ in 0..<800 {
            if !store.isWorking && !store.isGenerating && !store.isBakingMaterials { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw Failure.timeout
    }
    private func complete(_ command: any MTLCommandBuffer) async throws {
        await withCheckedContinuation { continuation in
            command.addCompletedHandler { _ in continuation.resume() }
            command.commit()
        }
        if let error = command.error { throw error }
        guard command.status == .completed else { throw Failure.incompleteGPU }
    }
    private func uploaded(_ texture: any MTLTexture, device: any MTLDevice) async throws -> Data {
        let row = texture.width * 4
        let output = try XCTUnwrap(
            device.makeBuffer(length: row * texture.height, options: .storageModeShared))
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let command = try XCTUnwrap(queue.makeCommandBuffer())
        let blit = try XCTUnwrap(command.makeBlitCommandEncoder())
        blit.copy(
            from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: .init(width: texture.width, height: texture.height, depth: 1), to: output,
            destinationOffset: 0, destinationBytesPerRow: row,
            destinationBytesPerImage: row * texture.height)
        blit.endEncoding()
        try await complete(command)
        return Data(bytes: output.contents(), count: row * texture.height)
    }
    private func render(_ renderer: TexturedMeshRenderer, device: any MTLDevice) async throws -> Data {
        let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb, width: size, height: size, mipmapped: false)
        colorDescriptor.usage = .renderTarget
        colorDescriptor.storageMode = .private
        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float, width: size, height: size, mipmapped: false)
        depthDescriptor.usage = .renderTarget
        depthDescriptor.storageMode = .private
        let color = try XCTUnwrap(device.makeTexture(descriptor: colorDescriptor))
        let depth = try XCTUnwrap(device.makeTexture(descriptor: depthDescriptor))
        let output = try XCTUnwrap(
            device.makeBuffer(length: size * size * 4, options: .storageModeShared))
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let command = try XCTUnwrap(queue.makeCommandBuffer())
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = color
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        let encoder = try XCTUnwrap(command.makeRenderCommandEncoder(descriptor: pass))
        renderer.encode(encoder: encoder, drawableSize: .init(width: size, height: size))
        encoder.endEncoding()
        let blit = try XCTUnwrap(command.makeBlitCommandEncoder())
        blit.copy(
            from: color, sourceSlice: 0, sourceLevel: 0, sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: .init(width: size, height: size, depth: 1), to: output, destinationOffset: 0,
            destinationBytesPerRow: size * 4, destinationBytesPerImage: size * size * 4)
        blit.endEncoding()
        try await complete(command)
        return Data(bytes: output.contents(), count: size * size * 4)
    }
    private func save(_ bytes: Data, name: String) throws {
        guard let output = ProcessInfo.processInfo.environment["DUST3D_UI_QA_OUTPUT_DIR"] else {
            return
        }
        let provider = try XCTUnwrap(CGDataProvider(data: bytes as CFData))
        let image = try XCTUnwrap(
            CGImage(
                width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: size * 4, space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(
                    .byteOrder32Little),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(
                URL(fileURLWithPath: output).appendingPathComponent(name + ".png") as CFURL,
                "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
    func testActualStoreGeneratedLegacyNormalUploadsLinearBytesAndChangesOnlyLightingAtFixedGeometry()
        async throws
    {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device") }
        // Hash/count guards for the root-reviewed family precede all native inputs.
        let inputs = try ReviewedSurfaceBake.inputs()
        let store = EditorStore(materialBaker: ReviewedSurfaceBake())
        defer { store.stop() }
        await store.load(data: try XCTUnwrap(inputs["cloth-start"]))
        try await settle(store)
        store.selectComponent(SurfaceDetailFixtureVariants.groupID)
        try await settle(store)
        let selected = try XCTUnwrap(store.snapshot)
        store.componentSurfaceAction(.scalar(.wrinkles, 1), target: .init(snapshot: selected))()
        try await settle(store)
        XCTAssertEqual(store.snapshot?.document.encoded(), inputs["cloth-action-full"])
        let baked = try XCTUnwrap(store.bakedMesh)
        let normal = try XCTUnwrap(baked.textures.normal)
        guard normal.width == 256, normal.height == 256, normal.rowStride == 1024 else {
            throw Failure.unexpectedMap
        }
        let control = MeshWithBakedTextures(
            geometry: baked.geometry, metadata: baked.metadata, tangents: baked.tangents,
            textures: MeshTextureMaps(
                color: baked.textures.color, normal: nil, metallic: baked.textures.metallic,
                roughness: baked.textures.roughness, emissive: baked.textures.emissive))
        let enabledOwner = try await TexturedMetalResourcesBuilder().make(
            bakedMesh: baked, device: device, camera: camera, maximumPayloadBytes: 64 * 1024 * 1024)
        XCTAssertTrue(enabledOwner.normalMapEnabled)
        let texture = enabledOwner.textures[1]
        XCTAssertEqual(texture.pixelFormat, .rgba8Unorm, "Generated tangent normals must remain linear")
        XCTAssertEqual(
            texture.mipmapLevelCount, 1,
            "This proof is production legacy base-only, not experimental source mip adoption")
        let bytes = try await uploaded(texture, device: device)
        XCTAssertEqual(bytes, normal.pixels)
        let omittedOwner = try await TexturedMetalResourcesBuilder().make(
            bakedMesh: control, device: device, camera: camera, maximumPayloadBytes: 64 * 1024 * 1024)
        XCTAssertFalse(omittedOwner.normalMapEnabled)
        let withNormal = try await render(TexturedMeshRenderer(resources: enabledOwner), device: device)
        let withoutNormal = try await render(
            TexturedMeshRenderer(resources: omittedOwner), device: device)
        var covered = 0
        var maximumDelta = 0
        var squared = 0.0
        for index in stride(from: 0, to: withNormal.count, by: 4) {
            XCTAssertEqual(
                withNormal[index + 3], withoutNormal[index + 3], "Geometry/alpha coverage must be identical"
            )
            guard withNormal[index + 3] == 255 else { continue }
            covered += 1
            for channel in 0..<3 {
                let delta = abs(Int(withNormal[index + channel]) - Int(withoutNormal[index + channel]))
                maximumDelta = max(maximumDelta, delta)
                squared += pow(Double(delta) / 255, 2)
            }
        }
        XCTAssertGreaterThan(covered, 100)
        XCTAssertGreaterThanOrEqual(
            maximumDelta, 3, "Ignored normal maps must fail this causal same-geometry comparison")
        print(
            "Pinned legacy generated normal: covered=\(covered), maxRGBDelta=\(maximumDelta), RMS=\(sqrt(squared / Double(max(1, covered * 3))))"
        )
        let revision = store.materialViewportRevision
        store.materialsRendered(revision: revision)
        XCTAssertNil(store.previewCompatibilityWarning)
        try save(withNormal, name: "surface-cloth-normal-enabled")
        try save(withoutNormal, name: "surface-cloth-normal-omitted")
    }
}
