import AppKit
import Dust3DDocument
import Metal
import MetalKit
import XCTest

@testable import Dust3DKit
@testable import Dust3DRendering

@MainActor
final class TexturedMetalRenderingTests: XCTestCase {
    func testShouldPreserveUnmappedPositiveSubnormalMaskAlpha() async throws {
        for alpha in [Float.leastNonzeroMagnitude, Float.leastNormalMagnitude.nextDown] {
            for cutoff in [Double(alpha), Double(alpha).nextUp] {
                let source = BakedMetalFixture.source(
                    try BakedMetalFixture.quad(
                        mapped: false, tangentMapped: false,
                        layers: [.init(color: SIMD4(1, 1, 1, alpha))]),
                    policy: .init(alphaMode: .mask, alphaCutoff: cutoff, isDoubleSided: true))
                let output = try await render(source)
                XCTAssertEqual(pixel(output, x: 64, y: 64)[3], Double(alpha) >= cutoff ? 255 : 0)
            }
        }
    }

    func testShouldClampUnmappedMaskAlphaBeforeScaledComparison() async throws {
        for (alpha, cutoff) in [
            (Float(2), 1.5), (.greatestFiniteMagnitude, 1.5), (2, 1),
            (-2, 0), (-Float.leastNonzeroMagnitude, Double.leastNonzeroMagnitude), (-0.0, 0),
        ] {
            let source = BakedMetalFixture.source(
                try BakedMetalFixture.quad(
                    mapped: false, tangentMapped: false,
                    layers: [.init(color: SIMD4(1, 1, 1, alpha))]),
                policy: .init(alphaMode: .mask, alphaCutoff: cutoff, isDoubleSided: true))
            let output = try await render(source)
            let clamped = min(Float(1), max(Float(0), alpha))
            XCTAssertEqual(
                pixel(output, x: 64, y: 64)[3], Double(clamped) >= cutoff ? 255 : 0,
                "alpha \(alpha), cutoff \(cutoff)")
        }
    }

    func testShouldKeepSourceMaskCutoffAboveAlphaAcrossDoubleToFloatConversion() async throws {
        for (alpha, cutoff) in [
            (Float(0.5), Double(0.5).nextUp), (Float(1), Double(1).nextUp), (Float(0), Double.leastNonzeroMagnitude),
        ] {
            let source = BakedMetalFixture.source(
                try BakedMetalFixture.quad(
                    mapped: false, tangentMapped: false,
                    layers: [.init(color: SIMD4(1, 1, 1, alpha))]),
                policy: .init(alphaMode: .mask, alphaCutoff: cutoff, isDoubleSided: true))
            let output = try await render(source)
            XCTAssertEqual(pixel(output, x: 64, y: 64)[3], 0)
        }
        for mode in [ImportedAlphaMode.opaque, .mask, .blend] {
            let source = BakedMetalFixture.source(
                try BakedMetalFixture.quad(
                    mapped: false, tangentMapped: false,
                    layers: [.init(color: SIMD4(1, 1, 1, 0.5))]),
                policy: .init(alphaMode: mode, alphaCutoff: Double.greatestFiniteMagnitude, isDoubleSided: true))
            let output = try await render(source)
            XCTAssertEqual(pixel(output, x: 64, y: 64)[3], mode == .mask ? 0 : mode == .opaque ? 255 : 128)
        }
    }

    func testShouldKeepUnknownSourceMappingOnVertexColorFallbackAndIgnoreAtlasSamples() async throws {
        let first = BakedMetalFixture.source(
            try BakedMetalFixture.quad(
                color: BakedMetalFixture.image([0, 0, 255, 0]), mapped: false, tangentMapped: false,
                layers: [.init(color: SIMD4(1, 0, 0, 0.5))]), policy: nil)
        let second = BakedMetalFixture.source(
            try BakedMetalFixture.quad(
                color: BakedMetalFixture.image([0, 255, 0, 255]), mapped: false, tangentMapped: false,
                layers: [.init(color: SIMD4(1, 0, 0, 0.5))]), policy: nil)
        let firstOutput = try await render(first)
        let secondOutput = try await render(second)
        XCTAssertEqual(firstOutput, secondOutput)
        let center = pixel(firstOutput, x: 64, y: 64)
        XCTAssertEqual(center[3], 128)
        XCTAssertGreaterThan(center[2], center[0])
    }

    func testShouldUpdateSourcePolicyBatchesTogetherWithCameraSortedIndices() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device is available") }
        let legacy = try BakedMetalFixture.quad(
            color: BakedMetalFixture.image([255, 0, 0, 128, 0, 0, 255, 128], width: 1, height: 2),
            layers: [.init(depth: 0.2, sample: SIMD2(0.5, 0.25)), .init(depth: -0.2, sample: SIMD2(0.5, 0.75))])
        let source = BakedMetalFixture.source(
            legacy,
            policyAt: { index in
                SourceBakedPolicy(alphaMode: .blend, alphaCutoff: 0.5, isDoubleSided: index >= 2)
            })
        let owner = try await TexturedMetalResourcesBuilder().make(
            bakedMesh: source, device: device,
            camera: OrbitCamera(yaw: 0, pitch: 0, distance: 3))
        XCTAssertTrue(owner.textures.allSatisfy { $0.mipmapLevelCount == 1 })
        let renderer = TexturedMeshRenderer(resources: owner)
        let front = try await pixels(renderer, device: device)
        XCTAssertEqual(pixel(front, x: 64, y: 64)[3], 192)
        renderer.camera.yaw = .pi
        await renderer.waitForPendingOrdering()
        XCTAssertNil(renderer.orderingError)
        let back = try await pixels(renderer, device: device)
        let center = pixel(back, x: 64, y: 64)
        XCTAssertEqual(center[3], 128)
        XCTAssertGreaterThan(
            center[0], center[2], "The blue double-sided layer must survive; the red single-sided layer is culled")
    }

    func testShouldDiscardMaskedFrontFragmentsWithoutOccludingOpaqueBackLayer() async throws {
        for alpha: UInt8 in [0, 128] {
            let legacy = try BakedMetalFixture.quad(
                color: BakedMetalFixture.image([255, 0, 0, alpha, 0, 0, 255, 255], width: 1, height: 2),
                layers: [.init(depth: 0.2, sample: SIMD2(0.5, 0.25)), .init(depth: -0.2, sample: SIMD2(0.5, 0.75))])
            let source = BakedMetalFixture.source(
                legacy,
                policyAt: { index in
                    SourceBakedPolicy(alphaMode: index < 2 ? .mask : .opaque, alphaCutoff: 0.5, isDoubleSided: true)
                })
            let output = try await render(source)
            let center = pixel(output, x: 64, y: 64)
            XCTAssertEqual(center[3], 255)
            if alpha == 0 {
                XCTAssertGreaterThan(center[0], center[2])
            } else {
                XCTAssertGreaterThan(center[2], center[0])
            }
        }
    }

    func testShouldHonorSourceOpaqueMaskAndBlendAlphaInProductionEncoder() async throws {
        for mode in [ImportedAlphaMode.opaque, .mask, .blend] {
            for alpha: UInt8 in [0, 1, 127, 128, 255] {
                let source = BakedMetalFixture.source(
                    try BakedMetalFixture.quad(color: BakedMetalFixture.image([255, 0, 0, alpha])),
                    policy: SourceBakedPolicy(alphaMode: mode, alphaCutoff: 0.5, isDoubleSided: true))
                let output = try await render(source)
                let center = pixel(output, x: 64, y: 64)
                let expected = mode == .opaque ? 255 : mode == .mask ? (alpha >= 128 ? 255 : 0) : Int(alpha)
                XCTAssertEqual(center[3], expected, "\(mode) source alpha \(alpha)")
                if mode == .opaque { XCTAssertGreaterThan(center[2], 0) }
            }
        }
        let zeroCutoff = BakedMetalFixture.source(
            try BakedMetalFixture.quad(color: BakedMetalFixture.image([255, 0, 0, 0])),
            policy: SourceBakedPolicy(alphaMode: .mask, alphaCutoff: 0, isDoubleSided: true))
        let zeroCutoffOutput = try await render(zeroCutoff)
        XCTAssertEqual(pixel(zeroCutoffOutput, x: 64, y: 64)[3], 255)
    }

    func testShouldCullSourceBackFacesOnlyWhenMaterialIsSingleSided() async throws {
        for doubleSided in [false, true] {
            let source = BakedMetalFixture.source(
                try BakedMetalFixture.quad(),
                policy: SourceBakedPolicy(alphaMode: .opaque, alphaCutoff: 0.5, isDoubleSided: doubleSided))
            let front = try await render(source)
            let back = try await render(source, camera: OrbitCamera(yaw: .pi, pitch: 0, distance: 3))
            XCTAssertEqual(pixel(front, x: 64, y: 64)[3], 255)
            XCTAssertEqual(pixel(back, x: 64, y: 64)[3], doubleSided ? 255 : 0)
        }
    }

    func testShouldRenderRealSourceBakedImportedAndProceduralArchives() async throws {
        for name in ["ImportedSurface", "Capsule"] {
            let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Dust3DKitTests/Fixtures/\(name).ds3")
            let source = try await ArchiveSourceTextureBakingService().load(
                data: Data(contentsOf: url),
                options: SourceMeshBakeOptions(
                    bake: MeshBakeOptions(colorSize: 256, normalSize: 128, materialSize: 256, atlasTextureSize: 256)))
            let output = try await render(source, camera: OrbitCamera())
            XCTAssertTrue(stride(from: 3, to: output.count, by: 4).contains { output[$0] > 0 })
            try saveArtifact(output, name: "source-baked-\(name)")
        }
    }

    func testShouldRenderAsymmetricAtlasInEncodedRowOrientation() async throws {
        let image = BakedMetalFixture.image(
            [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255], width: 2, height: 2)
        let pixels = try await render(BakedMetalFixture.quad(color: image))
        let topLeft = pixel(pixels, x: 50, y: 50)
        let topRight = pixel(pixels, x: 78, y: 50)
        let bottomLeft = pixel(pixels, x: 50, y: 78)
        XCTAssertGreaterThan(topLeft[2], topLeft[0] + 30)
        XCTAssertGreaterThan(topRight[1], topRight[2] + 30)
        XCTAssertGreaterThan(bottomLeft[0], bottomLeft[2] + 30)
        XCTAssertEqual(topLeft[3], 255)
        try saveArtifact(pixels, name: "baked-atlas-orientation")
    }

    func testShouldPreserveZeroLowAndPartialAlphaWithoutDepthOcclusion() async throws {
        for alpha: UInt8 in [0, 1, 128, 255] {
            let pixels = try await render(BakedMetalFixture.quad(color: BakedMetalFixture.image([255, 0, 0, alpha])))
            XCTAssertEqual(pixel(pixels, x: 64, y: 64)[3], Int(alpha))
            if alpha == 0 { XCTAssertTrue(pixels.allSatisfy { $0 == 0 }) }
        }
    }

    func testShouldSortTransparentLayersIndependentOfInputOrder() async throws {
        let image = BakedMetalFixture.image([255, 0, 0, 128, 0, 0, 255, 128], width: 1, height: 2)
        let layers = [
            BakedMetalFixture.Layer(depth: 0.2, sample: SIMD2(0.5, 0.25)), .init(depth: -0.2, sample: SIMD2(0.5, 0.75)),
        ]
        let forward = try await render(BakedMetalFixture.quad(color: image, layers: layers))
        let reverse = try await render(BakedMetalFixture.quad(color: image, layers: Array(layers.reversed())))
        XCTAssertEqual(forward, reverse)
        XCTAssertEqual(pixel(forward, x: 64, y: 64)[3], 192)
        XCTAssertGreaterThan(pixel(forward, x: 64, y: 64)[2], pixel(forward, x: 64, y: 64)[0])
    }

    func testShouldApplyMaterialMapsAndIgnoreMapsForMissingUVs() async throws {
        let base = BakedMetalFixture.image([80, 120, 180, 255])
        let neutral = try await render(BakedMetalFixture.quad(color: base))
        let explicitDefaults = try await render(
            BakedMetalFixture.quad(
                color: base, metallic: BakedMetalFixture.image([0, 0, 0, 255]),
                roughness: BakedMetalFixture.image([255, 255, 255, 255]),
                emissive: BakedMetalFixture.image([0, 0, 0, 255])))
        XCTAssertEqual(neutral, explicitDefaults)
        for (index, mesh) in [
            try BakedMetalFixture.quad(color: base, metallic: BakedMetalFixture.image([255, 255, 255, 255])),
            try BakedMetalFixture.quad(color: base, roughness: BakedMetalFixture.image([32, 32, 32, 255])),
            try BakedMetalFixture.quad(color: base, normal: BakedMetalFixture.image([255, 128, 128, 255])),
            try BakedMetalFixture.quad(color: base, emissive: BakedMetalFixture.image([0, 255, 0, 255])),
        ].enumerated() {
            let pixels = try await render(mesh)
            XCTAssertFalse(
                pixels == neutral, "Material map \(index) did not change shading; center \(pixel(pixels, x: 64, y: 64))"
            )
        }
        let missingFirst = try await render(BakedMetalFixture.quad(color: base, mapped: false))
        let missingSecond = try await render(
            BakedMetalFixture.quad(
                color: BakedMetalFixture.image([255, 0, 0, 0]),
                emissive: BakedMetalFixture.image([255, 255, 255, 255]), mapped: false))
        XCTAssertEqual(missingFirst, missingSecond)
    }

    func testShouldUpdateCameraOrderingAndDiscardSupersededSorts() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device is available") }
        let image = BakedMetalFixture.image([255, 0, 0, 128, 0, 0, 255, 128], width: 1, height: 2)
        let mesh = try BakedMetalFixture.quad(
            color: image,
            layers: [.init(depth: 0.2, sample: SIMD2(0.5, 0.25)), .init(depth: -0.2, sample: SIMD2(0.5, 0.75))])
        let owner = try await TexturedMetalResourcesBuilder().make(
            bakedMesh: mesh, device: device, camera: OrbitCamera(yaw: 0, pitch: 0, distance: 3))
        let renderer = TexturedMeshRenderer(resources: owner)
        let initial = try await pixels(renderer, device: device)
        for yaw: Float in [.pi, 0, .pi / 2, .pi] { renderer.camera.yaw = yaw }
        await renderer.waitForPendingOrdering()
        XCTAssertNil(renderer.orderingError)
        let rotated = try await pixels(renderer, device: device)
        XCTAssertGreaterThan(pixel(initial, x: 64, y: 64)[2], pixel(initial, x: 64, y: 64)[0])
        XCTAssertGreaterThan(pixel(rotated, x: 64, y: 64)[0], pixel(rotated, x: 64, y: 64)[2])
        XCTAssertEqual(pixel(rotated, x: 64, y: 64)[3], 192)
    }

    func testShouldApplyHandedNormalFramesAndIgnoreUnavailableTangents() async throws {
        let normal = BakedMetalFixture.image([128, 255, 128, 255])
        let positive = try await render(BakedMetalFixture.quad(normal: normal))
        let negative = try await render(BakedMetalFixture.quad(normal: normal, handedness: -1))
        XCTAssertGreaterThan(pixel(positive, x: 64, y: 64)[1], pixel(negative, x: 64, y: 64)[1] + 20)
        let ignored = try await render(BakedMetalFixture.quad(normal: normal, tangentMapped: false))
        let missing = try await render(BakedMetalFixture.quad(tangentMapped: false))
        XCTAssertTrue(ignored == missing)
        let emission = try await render(
            BakedMetalFixture.quad(
                color: BakedMetalFixture.image([0, 0, 0, 255]), emissive: BakedMetalFixture.image([0, 255, 0, 255])))
        let center = pixel(emission, x: 64, y: 64)
        XCTAssertGreaterThan(center[1], center[2] + 40)
        XCTAssertGreaterThan(center[1], center[0] + 40)
    }

    func testShouldRenderActualCoreBakeAndWireframeThroughProductionEncoder() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device is available") }
        let part = "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}"
        let xml =
            "<canvas originX='0' originY='0' originZ='0'><nodes><node id='{11111111-1111-4111-8111-111111111111}' partId='\(part)' x='0' y='0' z='0' radius='.1'/></nodes><edges/><parts><part id='\(part)' metallic='.5' roughness='.25' emissive='.2'/></parts><components><component id='{cccccccc-cccc-4ccc-8ccc-cccccccccccc}' linkDataType='partId' linkData='\(part)' color='#ff8000'/></components></canvas>"
        let data = try Dust3DDocument(snapshotXML: Data(xml.utf8)).encoded()
        let mesh = try await MeshBakingService().load(
            data: data, options: MeshBakeOptions(colorSize: 8, normalSize: 8, materialSize: 8))
        let owner = try await TexturedMetalResourcesBuilder().make(bakedMesh: mesh, device: device)
        let renderer = TexturedMeshRenderer(resources: owner)
        let solid = try await pixels(renderer, device: device)
        renderer.isWireframe = true
        let wire = try await pixels(renderer, device: device)
        let solidCoverage = stride(from: 3, to: solid.count, by: 4).filter { solid[$0] > 0 }.count
        let wireCoverage = stride(from: 3, to: wire.count, by: 4).filter { wire[$0] > 0 }.count
        XCTAssertGreaterThan(solidCoverage, 100)
        XCTAssertGreaterThan(wireCoverage, 0)
        XCTAssertLessThan(wireCoverage, solidCoverage)
        try saveArtifact(solid, name: "baked-core-material-solid")
        try saveArtifact(wire, name: "baked-core-material-wireframe")
    }

    func testShouldCancelBeforeResourceCreationAndReleasePendingRenderer() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device is available") }
        let mesh = try BakedMetalFixture.quad(color: BakedMetalFixture.image([255, 0, 0, 128]))
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            let owner = try await TexturedMetalResourcesBuilder().make(bakedMesh: mesh, device: device)
            return TexturedMeshRenderer(resources: owner)
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        let owner = try await TexturedMetalResourcesBuilder().make(bakedMesh: mesh, device: device)
        var renderer: TexturedMeshRenderer? = TexturedMeshRenderer(resources: owner)
        weak var reference: TexturedMeshRenderer?
        reference = renderer
        renderer?.camera.yaw = 1
        renderer = nil
        XCTAssertNil(reference)
    }

    func testShouldWriteOpaqueDepthAndSurfaceOrderingFailuresWithoutLosingCause() async throws {
        let layers = [
            BakedMetalFixture.Layer(depth: 0.2, color: SIMD4(1, 0, 0, 1)), .init(depth: -0.2, color: SIMD4(0, 0, 1, 1)),
        ]
        let first = try await render(BakedMetalFixture.quad(mapped: false, layers: layers))
        let second = try await render(BakedMetalFixture.quad(mapped: false, layers: Array(layers.reversed())))
        XCTAssertTrue(first == second)
        XCTAssertGreaterThan(pixel(first, x: 64, y: 64)[2], pixel(first, x: 64, y: 64)[0] + 30)
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device is available") }
        let mesh = try BakedMetalFixture.quad(color: BakedMetalFixture.image([255, 0, 0, 128]))
        let owner = try await TexturedMetalResourcesBuilder().make(bakedMesh: mesh, device: device)
        let renderer = TexturedMeshRenderer(resources: owner)
        var cause: (any Error)?
        renderer.onError = { cause = $0 }
        renderer.camera.yaw = .nan
        await renderer.waitForPendingOrdering()
        XCTAssertEqual(renderer.orderingError as? BakedMetalPreparationError, .invalidCamera)
        XCTAssertEqual(cause as? BakedMetalPreparationError, .invalidCamera)
        renderer.camera.yaw = 0
        await renderer.waitForPendingOrdering()
        XCTAssertNil(renderer.orderingError)
        let view = MTKView(frame: .zero, device: device)
        renderer.draw(in: view)
        guard case .unavailable(let message) = renderer.renderingError as? BakedMetalPreparationError else {
            return XCTFail("Expected an explicit target format diagnostic")
        }
        XCTAssertTrue(message.contains("sRGB"))
    }

    private func saveArtifact(_ pixels: [UInt8], name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["DUST3D_METAL_QA_OUTPUT_DIR"] else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let image = try XCTUnwrap(
            CGImage(
                width: 128, height: 128, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 512,
                space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(
                    .byteOrder32Little),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent(name + ".png"))
    }

    private func pixel(_ bytes: [UInt8], x: Int, y: Int) -> [Int] {
        let offset = (y * 128 + x) * 4
        return bytes[offset..<offset + 4].map(Int.init)
    }

    private func render(_ mesh: MeshWithBakedTextures) async throws -> [UInt8] {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device is available") }
        let owner = try await TexturedMetalResourcesBuilder().make(
            bakedMesh: mesh, device: device, camera: OrbitCamera(yaw: 0, pitch: 0, distance: 3))
        let renderer = TexturedMeshRenderer(resources: owner)
        return try await pixels(renderer, device: device)
    }

    private func render(_ mesh: SourceBakedMesh, camera: OrbitCamera = OrbitCamera(yaw: 0, pitch: 0, distance: 3))
        async throws -> [UInt8]
    {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device is available") }
        let owner = try await TexturedMetalResourcesBuilder().make(bakedMesh: mesh, device: device, camera: camera)
        return try await pixels(TexturedMeshRenderer(resources: owner), device: device)
    }

    private func pixels(_ renderer: TexturedMeshRenderer, device: any MTLDevice) async throws -> [UInt8] {
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
