import AppKit
import Dust3DDocument
import Dust3DKit
import Metal
import XCTest

@testable import Dust3DRendering

@MainActor
final class IndexedMetalRenderingTests: XCTestCase {
    func testIndexedAndExpandedProductionPassesRenderTheSameSolidAndWireframe() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device is available") }
        var document = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        document = try document.applying(
            .addNode(
                id: "{11111111-1111-4111-8111-111111111111}", partID: "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}",
                componentID: "{cccccccc-cccc-4ccc-8ccc-cccccccccccc}", position: .init(x: 0.5, y: 0.5, z: 0.5),
                radius: 0.2))
        let data = document.encoded()
        let expanded = try MeshLoader.load(data: data)
        let indexed = try MeshLoader.loadIndexed(data: data)
        XCTAssertLessThan(indexed.vertices.count, expanded.vertices.count)
        let reference = try MeshRenderer(mesh: .expanded(expanded), device: device)
        let candidate = try MeshRenderer(mesh: .indexed(indexed), device: device)
        var solidCoverage = 0
        for wireframe in [false, true] {
            reference.isWireframe = wireframe
            candidate.isWireframe = wireframe
            let expected = try pixels(reference, device: device)
            let actual = try pixels(candidate, device: device)
            XCTAssertEqual(actual, expected, "Indexed drawing changed the offscreen production pass")
            try saveArtifact(actual, name: wireframe ? "indexed-wireframe" : "indexed-solid")
            let coverage = stride(from: 3, to: actual.count, by: 4).filter { actual[$0] != 0 }.count
            XCTAssertGreaterThan(coverage, 20)
            if wireframe { XCTAssertLessThan(coverage, solidCoverage) } else { solidCoverage = coverage }
        }
    }

    private func saveArtifact(_ pixels: [UInt8], name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["DUST3D_METAL_QA_OUTPUT_DIR"] else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let image = try XCTUnwrap(
            CGImage(
                width: 128, height: 128, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: 512, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(
                    .byteOrder32Little),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent(name + ".png"))
    }

    private func pixels(_ renderer: MeshRenderer, device: MTLDevice) throws -> [UInt8] {
        let width = 128
        let height = 128
        let rowBytes = width * 4
        let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        colorDescriptor.usage = [.renderTarget]
        colorDescriptor.storageMode = .private
        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float, width: width, height: height, mipmapped: false)
        depthDescriptor.usage = [.renderTarget]
        depthDescriptor.storageMode = .private
        let color = try XCTUnwrap(device.makeTexture(descriptor: colorDescriptor))
        let depth = try XCTUnwrap(device.makeTexture(descriptor: depthDescriptor))
        let destination = try XCTUnwrap(device.makeBuffer(length: rowBytes * height, options: .storageModeShared))
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let command = try XCTUnwrap(queue.makeCommandBuffer())
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = color
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .dontCare
        pass.depthAttachment.clearDepth = 1
        let encoder = try XCTUnwrap(command.makeRenderCommandEncoder(descriptor: pass))
        renderer.encode(encoder: encoder, drawableSize: CGSize(width: width, height: height))
        encoder.endEncoding()
        let blit = try XCTUnwrap(command.makeBlitCommandEncoder())
        blit.copy(
            from: color, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: width, height: height, depth: 1), to: destination,
            destinationOffset: 0, destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * height)
        blit.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        XCTAssertEqual(command.status, .completed, command.error?.localizedDescription ?? "GPU pass did not complete")
        return Array(
            UnsafeBufferPointer(
                start: destination.contents().assumingMemoryBound(to: UInt8.self), count: rowBytes * height))
    }
}
