import Foundation
import Metal
import XCTest

@testable import Dust3DKit
@testable import Dust3DRendering

@MainActor
final class MetalMipSamplingTests: XCTestCase {
    func testUploadsEveryLevelAndUsesTrilinearSamplingWithinTheProducerCap() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device is available") }
        let base = image(side: 4, rgba: [255, 0, 0, 255])
        let chain = try TextureMipChain(
            levels: [base, image(side: 2, rgba: [0, 255, 0, 255]), image(side: 1, rgba: [0, 0, 255, 255])],
            maximumSamplingLod: 2)
        let original = BakedMetalFixture.source(try BakedMetalFixture.quad(color: base), policy: nil)
        for cap in [2.0, 0.5] {
            let mesh = SourceBakedMesh(
                geometry: original.geometry, triangles: original.triangles, modelIDs: [], components: [],
                textures: original.textures, maximumSamplingLod: cap, nativePayloadBytes: 0, copiedPayloadBytes: 0)
            let resources = try await TexturedMetalResourcesBuilder().make(
                bakedMesh: mesh, device: device, mipmaps: [0: chain])
            XCTAssertEqual(resources.textures[0].mipmapLevelCount, 3)
            XCTAssertEqual(resources.textures[1].mipmapLevelCount, 1, "Absent normal maps remain constant fallbacks")
            let source = """
                #include <metal_stdlib>
                using namespace metal;
                kernel void inspectMips(texture2d<float> image [[texture(0)]], sampler filtering [[sampler(0)]],
                    device float4 *output [[buffer(0)]], uint index [[thread_position_in_grid]]) {
                    output[index] = image.sample(filtering, float2(.5), level(index == 0 ? .5f : 99.0f));
                }
                """
            let library = try await device.makeLibrary(source: source, options: nil)
            let function = try XCTUnwrap(library.makeFunction(name: "inspectMips"))
            let pipeline = try await device.makeComputePipelineState(function: function)
            let output = try XCTUnwrap(
                device.makeBuffer(length: 8 * MemoryLayout<Float>.stride, options: .storageModeShared))
            let command = try XCTUnwrap(resources.queue.makeCommandBuffer())
            let encoder = try XCTUnwrap(command.makeComputeCommandEncoder())
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(resources.textures[0], index: 0)
            encoder.setSamplerState(resources.sampler, index: 0)
            encoder.setBuffer(output, offset: 0, index: 0)
            encoder.dispatchThreads(
                MTLSize(width: 2, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
            encoder.endEncoding()
            await withCheckedContinuation { continuation in
                command.addCompletedHandler { _ in continuation.resume() }
                command.commit()
            }
            XCTAssertEqual(
                command.status, .completed, command.error?.localizedDescription ?? "Mip sampling did not complete")
            let samples = output.contents().assumingMemoryBound(to: Float.self)
            XCTAssertEqual(samples[0], 0.5, accuracy: 0.002)
            XCTAssertEqual(samples[1], 0.5, accuracy: 0.002)
            XCTAssertEqual(samples[2], 0, accuracy: 0.002)
            XCTAssertEqual(samples[3], 1, accuracy: 0.002)
            if cap == 2 {
                XCTAssertEqual(samples[4], 0, accuracy: 0.002)
                XCTAssertEqual(samples[5], 0, accuracy: 0.002)
                XCTAssertEqual(samples[6], 1, accuracy: 0.002)
            } else {
                XCTAssertEqual(samples[4], 0.5, accuracy: 0.002)
                XCTAssertEqual(samples[5], 0.5, accuracy: 0.002)
                XCTAssertEqual(samples[6], 0, accuracy: 0.002)
            }
        }
    }

    private func image(side: Int, rgba: [UInt8]) -> MeshTextureImage {
        BakedMetalFixture.image(Array(repeating: rgba, count: side * side).flatMap { $0 }, width: side, height: side)
    }
}
