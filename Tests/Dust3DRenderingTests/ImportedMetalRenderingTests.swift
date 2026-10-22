import AppKit
import Metal
import MetalKit
import XCTest

@testable import Dust3DKit
@testable import Dust3DRendering

@MainActor
final class ImportedMetalRenderingTests: XCTestCase {
    func testShouldCompareMaskAlphaAgainstOriginalDoubleCutoffWithoutRoundingDown() async throws {
        for (alpha, cutoff) in [
            (0.5, Double(0.5).nextUp), (1.0, Double(1).nextUp), (0.0, Double.leastNonzeroMagnitude),
        ] {
            let output = try await render(
                ImportedMetalFixture.quad(
                    mode: .mask,
                    baseColor: SIMD4(1, 1, 1, alpha), cutoff: cutoff))
            XCTAssertEqual(pixel(output)[3], 0, "Alpha \(alpha) must remain below the original cutoff \(cutoff)")
        }
        for mode in [ImportedAlphaMode.opaque, .mask, .blend] {
            let output = try await render(
                ImportedMetalFixture.quad(
                    mode: mode,
                    baseColor: SIMD4(1, 1, 1, 0.5), cutoff: Double.greatestFiniteMagnitude))
            XCTAssertEqual(pixel(output)[3], mode == .mask ? 0 : mode == .opaque ? 255 : 128)
        }
    }

    func testShouldPreservePositiveSubnormalMaskAlphaFactors() async throws {
        for alpha in [Float.leastNonzeroMagnitude, Float.leastNormalMagnitude.nextDown] {
            for isVertex in [false, true] {
                for cutoff in [Double(alpha), Double(alpha).nextUp] {
                    let output = try await render(
                        ImportedMetalFixture.quad(
                            mode: .mask, baseColor: SIMD4(1, 1, 1, isVertex ? 1 : Double(alpha)),
                            color: SIMD4(1, 1, 1, isVertex ? Double(alpha) : 1), cutoff: cutoff))
                    XCTAssertEqual(
                        pixel(output)[3], Double(alpha) >= cutoff ? 255 : 0,
                        "alpha \(alpha), vertex \(isVertex), cutoff \(cutoff)")
                }
            }
        }
    }

    func testShouldRoundSubnormalMaskProductsWithoutFlushingFactors() async throws {
        let smallest = Float.leastNonzeroMagnitude
        for (vertexAlpha, materialAlpha, textureAlpha) in [
            (smallest, Float(0.5), UInt8(255)), (smallest, Float(0.75), UInt8(255)),
            (smallest * 2, Float(0.5), UInt8(255)), (smallest, Float(1), UInt8(128)),
            (smallest * 2, Float(0.75), UInt8(255)),
        ] {
            let alpha = (Float(textureAlpha) / 255 * vertexAlpha) * materialAlpha
            for cutoff in [Double(smallest), Double(smallest * 2)] {
                let output = try await render(
                    ImportedMetalFixture.quad(
                        mode: .mask, baseColor: SIMD4(1, 1, 1, Double(materialAlpha)),
                        color: SIMD4(1, 1, 1, Double(vertexAlpha)), cutoff: cutoff,
                        layers: [.init(rgba: [255, 0, 0, textureAlpha])]))
                XCTAssertEqual(
                    pixel(output)[3], Double(alpha) >= cutoff ? 255 : 0,
                    "vertex \(vertexAlpha), material \(materialAlpha), texture \(textureAlpha), cutoff \(cutoff)")
            }
        }
    }

    func test_should_sample_source_image_in_encoded_row_orientation() async throws {
        let pixels = try await render(
            ImportedMetalFixture.quad(layers: [
                .init(pixels: [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255])
            ]))
        let topLeft = pixel(pixels, x: 50, y: 50)
        let topRight = pixel(pixels, x: 78, y: 50)
        let bottomLeft = pixel(pixels, x: 50, y: 78)
        XCTAssertGreaterThan(topLeft[2], topLeft[0] + 30)
        XCTAssertGreaterThan(topRight[1], topRight[2] + 30)
        XCTAssertGreaterThan(bottomLeft[0], bottomLeft[2] + 30)
        XCTAssertEqual(topLeft[3], 255)
    }

    func test_should_apply_straight_alpha_factors_and_opaque_mask_blend_policy() async throws {
        let layer = ImportedMetalFixture.Layer(rgba: [255, 0, 0, 128])
        let factor = SIMD4<Double>(1, 1, 1, 0.5)
        let color = SIMD4<Double>(1, 1, 1, 0.5)
        let opaque = try await render(
            ImportedMetalFixture.quad(mode: .opaque, baseColor: factor, color: color, layers: [layer]))
        let blend = try await render(
            ImportedMetalFixture.quad(mode: .blend, baseColor: factor, color: color, layers: [layer]))
        let rejected = try await render(
            ImportedMetalFixture.quad(mode: .mask, baseColor: factor, color: color, cutoff: 0.5, layers: [layer]))
        let accepted = try await render(
            ImportedMetalFixture.quad(mode: .mask, baseColor: factor, color: color, cutoff: 0.1, layers: [layer]))
        XCTAssertEqual(pixel(opaque)[3], 255)
        XCTAssertEqual(pixel(blend)[3], 32)
        XCTAssertEqual(pixel(rejected)[3], 0)
        XCTAssertEqual(pixel(accepted)[3], 255)
    }

    func test_should_sort_different_model_textures_globally_and_reorder_with_camera() async throws {
        let layers = [
            ImportedMetalFixture.Layer(depth: 0.2, rgba: [255, 0, 0, 128]), .init(depth: -0.2, rgba: [0, 0, 255, 128]),
        ]
        let forward = try await render(ImportedMetalFixture.quad(mode: .blend, doubleSided: true, layers: layers))
        let reverse = try await render(
            ImportedMetalFixture.quad(mode: .blend, doubleSided: true, layers: Array(layers.reversed())))
        XCTAssertTrue(forward == reverse, "Blended model order changed the rendered result")
        XCTAssertEqual(pixel(forward)[3], 192)
        XCTAssertGreaterThan(pixel(forward)[2], pixel(forward)[0])
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device is available") }
        let owner = try await ImportedMetalResourcesBuilder().make(
            data: ImportedMetalFixture.quad(mode: .blend, doubleSided: true, layers: layers), device: device,
            camera: OrbitCamera(yaw: 0, pitch: 0, distance: 3))
        let renderer = ImportedMeshRenderer(resources: owner)
        for yaw: Float in [.pi, 0, .pi / 2, .pi] { renderer.camera.yaw = yaw }
        await renderer.waitForPendingOrdering()
        XCTAssertNil(renderer.orderingError)
        let rotated = try await pixels(renderer, device: device)
        XCTAssertGreaterThan(pixel(rotated)[0], pixel(rotated)[2])
    }

    func test_should_cull_backfaces_unless_material_is_double_sided_and_render_wireframe() async throws {
        let front = try await render(ImportedMetalFixture.quad())
        let back = try await render(ImportedMetalFixture.quad(reversed: true))
        let both = try await render(ImportedMetalFixture.quad(doubleSided: true, reversed: true))
        XCTAssertGreaterThan(pixel(front)[3], 0)
        XCTAssertEqual(pixel(back)[3], 0)
        XCTAssertGreaterThan(pixel(both)[3], 0)
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device is available") }
        let owner = try await ImportedMetalResourcesBuilder().make(
            data: ImportedMetalFixture.quad(), device: device, camera: OrbitCamera(yaw: 0, pitch: 0, distance: 3))
        let renderer = ImportedMeshRenderer(resources: owner)
        let solid = try await pixels(renderer, device: device)
        renderer.isWireframe = true
        let wire = try await pixels(renderer, device: device)
        let solidCoverage = stride(from: 3, to: solid.count, by: 4).filter { solid[$0] > 0 }.count
        let wireCoverage = stride(from: 3, to: wire.count, by: 4).filter { wire[$0] > 0 }.count
        XCTAssertGreaterThan(wireCoverage, 0)
        XCTAssertLessThan(wireCoverage, solidCoverage)
    }

    func test_should_preserve_upload_cancellation_and_camera_error_causes() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device is available") }
        let data = try ImportedMetalFixture.quad(mode: .blend)
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            let owner = try await ImportedMetalResourcesBuilder().make(data: data, device: device)
            return ImportedMeshRenderer(resources: owner)
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancelled upload")
        } catch { XCTAssertTrue(error is CancellationError) }
        let owner = try await ImportedMetalResourcesBuilder().make(data: data, device: device)
        let renderer = ImportedMeshRenderer(resources: owner)
        var cause: (any Error)?
        renderer.onError = { cause = $0 }
        renderer.camera.yaw = .nan
        await renderer.waitForPendingOrdering()
        XCTAssertEqual(renderer.orderingError as? ImportedRenderError, .invalidCamera)
        XCTAssertEqual(cause as? ImportedRenderError, .invalidCamera)
    }

    func test_should_upload_actual_owned_glb_source_and_generate_requested_mipmaps() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device is available") }
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Dust3DKitTests/Fixtures/ImportedSurface.ds3")
        let data = try XCTUnwrap(ImportedMaterialRenderLoader.loadIfPresent(data: Data(contentsOf: url)))
        let owner = try await ImportedMetalResourcesBuilder().make(
            data: data, device: device, camera: OrbitCamera(yaw: 0, pitch: 0, distance: 3))
        let levels = owner.materials[0].texture.mipmapLevelCount
        XCTAssertEqual(levels, 2)
        let renderer = ImportedMeshRenderer(resources: owner)
        let output = try await pixels(renderer, device: device)
        XCTAssertGreaterThan(stride(from: 3, to: output.count, by: 4).filter { output[$0] > 0 }.count, 0)
    }

    func test_should_apply_repeat_mirror_and_clamp_on_each_texture_axis() async throws {
        let pixels: [UInt8] = [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255]
        let cases: [(ImportedTextureWrapMode, ImportedTextureWrapMode, SIMD2<Double>, Int)] = [
            (.repeatTexture, .clampToEdge, SIMD2(1.25, 0.25), 2),
            (.clampToEdge, .clampToEdge, SIMD2(1.25, 0.25), 1),
            (.mirroredRepeat, .clampToEdge, SIMD2(1.25, 0.25), 1),
            (.repeatTexture, .clampToEdge, SIMD2(-0.25, 0.25), 1),
            (.mirroredRepeat, .clampToEdge, SIMD2(-0.25, 0.25), 2),
            (.clampToEdge, .repeatTexture, SIMD2(0.25, -0.25), 0),
            (.clampToEdge, .mirroredRepeat, SIMD2(0.25, -0.25), 2),
        ]
        for (wrapS, wrapT, sample, channel) in cases {
            let sampler = ImportedTextureSampler(
                magnification: .nearest, minification: .nearest, wrapS: wrapS, wrapT: wrapT)
            let output = try await render(
                ImportedMetalFixture.quad(sampler: sampler, sample: sample, layers: [.init(pixels: pixels)]))
            let center = pixel(output)
            for other in 0..<3 where other != channel { XCTAssertGreaterThan(center[channel], center[other] + 30) }
        }
    }

    func test_should_filter_decoded_srgb_before_linear_factor_composition() async throws {
        let sampler = ImportedTextureSampler(
            magnification: .linear, minification: .linear, wrapS: .clampToEdge, wrapT: .clampToEdge)
        let samples: [UInt8] = [0, 0, 0, 255, 128, 128, 128, 255, 0, 0, 0, 255, 128, 128, 128, 255]
        let filtered = try await render(
            ImportedMetalFixture.quad(sampler: sampler, sample: SIMD2(0.5, 0.5), layers: [.init(pixels: samples)]))
        // Independent linear factor equals half of inverse-sRGB(128/255), not inverse-sRGB(64/255).
        let reference = try await render(
            ImportedMetalFixture.quad(baseColor: SIMD4(0.10793025, 0.10793025, 0.10793025, 1), hasImage: false))
        for channel in 0..<3 { XCTAssertEqual(pixel(filtered)[channel], pixel(reference)[channel], accuracy: 2) }
    }

    func test_should_apply_linear_color_and_pbr_scalar_factors() async throws {
        let neutral = try await render(ImportedMetalFixture.quad(baseColor: SIMD4(0.5, 0.5, 0.5, 1), hasImage: false))
        let dark = try await render(ImportedMetalFixture.quad(baseColor: SIMD4(0.125, 0.25, 0.375, 1), hasImage: false))
        for channel in 0..<3 { XCTAssertLessThan(pixel(dark)[channel], pixel(neutral)[channel]) }
        let metal = try await render(
            ImportedMetalFixture.quad(baseColor: SIMD4(0.5, 0.5, 0.5, 1), metallic: 1, hasImage: false))
        let gloss = try await render(
            ImportedMetalFixture.quad(baseColor: SIMD4(0.5, 0.5, 0.5, 1), roughness: 0.1, hasImage: false))
        XCTAssertFalse(metal == neutral, "Metallic factor did not affect shading")
        XCTAssertFalse(gloss == neutral, "Roughness factor did not affect shading")
        let emission = try await render(
            ImportedMetalFixture.quad(baseColor: SIMD4(0, 0, 0, 1), emissive: SIMD3(0, 1, 0), hasImage: false))
        XCTAssertGreaterThan(pixel(emission)[1], pixel(emission)[0] + 30)
        XCTAssertGreaterThan(pixel(emission)[1], pixel(emission)[2] + 30)
    }

    func test_should_minify_through_linear_srgb_mips_against_a_linear_factor_reference() async throws {
        let size = 512
        var checker: [UInt8] = []
        checker.reserveCapacity(size * size * 4)
        for row in 0..<size {
            for column in 0..<size {
                let value: UInt8 = (row + column).isMultiple(of: 2) ? 0 : 255
                checker.append(contentsOf: [value, value, value, 255])
            }
        }
        let sampler = ImportedTextureSampler(
            magnification: .nearest, minification: .linearMipmapLinear, wrapS: .repeatTexture, wrapT: .repeatTexture)
        let minified = try await render(
            ImportedMetalFixture.quad(sampler: sampler, layers: [.init(pixels: checker, width: size, height: size)]))
        let reference = try await render(ImportedMetalFixture.quad(baseColor: SIMD4(0.5, 0.5, 0.5, 1), hasImage: false))
        for channel in 0..<3 { XCTAssertEqual(pixel(minified)[channel], pixel(reference)[channel], accuracy: 2) }
    }

    private func pixel(_ bytes: [UInt8], x: Int = 64, y: Int = 64) -> [Int] {
        let offset = (y * 128 + x) * 4
        return bytes[offset..<offset + 4].map(Int.init)
    }

    private func render(_ data: ImportedMaterialRenderData) async throws -> [UInt8] {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device is available") }
        let owner = try await ImportedMetalResourcesBuilder().make(
            data: data, device: device, camera: OrbitCamera(yaw: 0, pitch: 0, distance: 3))
        return try await pixels(ImportedMeshRenderer(resources: owner), device: device)
    }

    private func pixels(_ renderer: ImportedMeshRenderer, device: any MTLDevice) async throws -> [UInt8] {
        let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb, width: 128, height: 128, mipmapped: false)
        colorDescriptor.usage = .renderTarget
        colorDescriptor.storageMode = .private
        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float, width: 128, height: 128, mipmapped: false)
        depthDescriptor.usage = .renderTarget
        depthDescriptor.storageMode = .private
        let color = try XCTUnwrap(device.makeTexture(descriptor: colorDescriptor))
        let depth = try XCTUnwrap(device.makeTexture(descriptor: depthDescriptor))
        let destination = try XCTUnwrap(device.makeBuffer(length: 128 * 128 * 4, options: .storageModeShared))
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
        renderer.encode(encoder: encoder, drawableSize: CGSize(width: 128, height: 128))
        encoder.endEncoding()
        let blit = try XCTUnwrap(command.makeBlitCommandEncoder())
        blit.copy(
            from: color, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: 128, height: 128, depth: 1), to: destination, destinationOffset: 0,
            destinationBytesPerRow: 512, destinationBytesPerImage: 65536)
        blit.endEncoding()
        // Keep the non-Sendable command on the main actor; only the continuation crosses the SDK callback.
        await withCheckedContinuation { continuation in
            command.addCompletedHandler { _ in continuation.resume() }
            command.commit()
        }
        XCTAssertEqual(
            command.status, .completed, command.error?.localizedDescription ?? "GPU rendering did not complete")
        return Array(
            UnsafeBufferPointer(start: destination.contents().assumingMemoryBound(to: UInt8.self), count: 65536))
    }
}
