#if MOTE3D_EXPERIMENTAL_FISH_IDLE && MOTE3D_EXPERIMENTAL_GENERATED_RIG
    import CryptoKit
    import Dust3DDocument
    import Dust3DEditorModel
    import Dust3DKit
    import Foundation
    import Metal
    import XCTest

    @testable import Dust3DEditor
    @testable import Dust3DRendering

    /// Exercises copied native animation through the controller and production Metal pass, without a window.
    @MainActor
    final class NativeAnimationFamilyMetalTests: XCTestCase {
        private struct Manifest: Decodable {
            let coreRevision: String
            let families: [Fixture]
        }

        private struct Clip: Decodable {
            let id: String
            let type: String
            let duration: Double
            let authoredFrameCount: Int
        }

        private struct Fixture: Decodable {
            let name: String
            let family: String
            let archivePath: String
            let archiveSHA256: String
            let archiveBytes: Int
            let moving: Clip
            let idle: Clip
        }

        private let limits = FishIdleCopyLimits(
            nativeBytes: 64 * 1024 * 1024, swiftBytes: 64 * 1024 * 1024,
            combinedBytes: 128 * 1024 * 1024)

        func testBirdRendersCopiedNativePoses() async throws { try await verify("Bird") }
        func testQuadrupedRendersCopiedNativePoses() async throws { try await verify("Quadruped") }
        func testBipedRendersCopiedNativePoses() async throws { try await verify("Biped") }
        func testFishRendersCopiedNativePoses() async throws { try await verify("Fish") }
        func testInsectRendersCopiedNativePoses() async throws { try await verify("Insect") }
        func testSnakeRendersCopiedNativePoses() async throws { try await verify("Snake") }
        func testSpiderRendersCopiedNativePoses() async throws { try await verify("Spider") }

        private func verify(_ family: String) async throws {
            guard let device = MTLCreateSystemDefaultDevice() else {
                throw XCTSkip("No Metal device is available for the actual offscreen animation pass")
            }
            let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Dust3DKitTests/Fixtures/AnimationFamilies")
            let manifest = try JSONDecoder().decode(
                Manifest.self, from: Data(contentsOf: directory.appendingPathComponent("manifest.json")))
            XCTAssertEqual(manifest.coreRevision, "0d93595fb359de8eecfd33046d1a7b09eafee46d")
            let fixture = try XCTUnwrap(manifest.families.first { $0.family == family })
            let bytes = try Data(contentsOf: directory.appendingPathComponent(fixture.archivePath))
            XCTAssertEqual(bytes.count, fixture.archiveBytes)
            XCTAssertLessThanOrEqual(bytes.count, 128 * 1024)
            XCTAssertEqual(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), fixture.archiveSHA256)
            let document = try Dust3DDocument(data: bytes)
            let snapshot = try await EditorSession().open(data: bytes)
            let rigRequest = GeneratedRigPreviewRequest(snapshot: snapshot)
            XCTAssertEqual(rigRequest.sourceType, family)
            let fileIdentity = UUID()
            let rigRevision = UUID()
            func source(_ expected: Clip) throws -> SuppliedAnimationSource {
                let animation = try XCTUnwrap(document.animations().first { $0.id == expected.id })
                XCTAssertEqual(animation.type, expected.type)
                return SuppliedAnimationSource(
                    playbackRequest: .init(
                        fileIdentity: fileIdentity, rig: rigRequest, animation: animation, queryID: UUID()),
                    rigRevision: rigRevision)
            }
            let movingSource = try source(fixture.moving)

            let clip = try await ExperimentalFishIdleClipService().load(
                source: movingSource, includePCM: false, limits: limits)
            XCTAssertEqual(clip.source, movingSource)
            let preview = SuppliedAnimationPreview()
            defer { preview.stop() }
            let lease = preview.install(clip)
            var frames: [SuppliedAnimationFrame] = []
            for fraction in [0.0, 0.25, 0.5, 0.75] {
                let result = await preview.sample(
                    .scrub(fixture.moving.duration * fraction), lease: lease, currentSource: { movingSource })
                let frame = try XCTUnwrap(result).get()
                XCTAssertEqual(frame.lease, lease)
                frames.append(frame)
            }
            let first = try XCTUnwrap(frames.first)
            XCTAssertFalse(first.mesh.vertices.isEmpty)
            XCTAssertTrue(
                frames.dropFirst().contains { frame in
                    zip(first.mesh.vertices, frame.mesh.vertices).contains { before, after in
                        let delta = after.position - before.position
                        return abs(delta.x) > 0.00001 || abs(delta.y) > 0.00001 || abs(delta.z) > 0.00001
                    }
                }, "\(family) must retain actual CPU deformation before GPU proof")

            var changedForegroundPixels = 0
            var changedSilhouettePixels = 0
            // Fixed views expose different projected motion; neither follows or refits an animated pose.
            for camera in [OrbitCamera(yaw: -0.35, pitch: 0.25), OrbitCamera(yaw: 1.2, pitch: 0.4)] {
                let renderer = try MeshRenderer(
                    mesh: .expanded(first.mesh), device: device, referenceBounds: first.restBounds)
                renderer.camera = camera
                renderer.animationGroundOffset = nil
                let initialPixels = try pixels(renderer, device: device)
                XCTAssertGreaterThan(foregroundCount(initialPixels), 16, "\(family) must rasterize visible geometry")
                for frame in frames.dropFirst() {
                    XCTAssertEqual(frame.restBounds.center, first.restBounds.center)
                    XCTAssertEqual(frame.restBounds.radius, first.restBounds.radius)
                    XCTAssertEqual(frame.mesh.vertices.count, first.mesh.vertices.count)
                    try renderer.replaceAnimationFrame(mesh: frame.mesh, groundOffset: frame.groundOffset)
                    // replaceAnimationFrame publishes the ground atomically. Disable it for body-only evidence.
                    renderer.animationGroundOffset = nil
                    XCTAssertEqual(renderer.camera.yaw, camera.yaw)
                    XCTAssertEqual(renderer.camera.pitch, camera.pitch)
                    XCTAssertEqual(renderer.camera.distance, camera.distance)
                    let actual = try pixels(renderer, device: device)
                    XCTAssertGreaterThan(foregroundCount(actual), 16)
                    let independent = try MeshRenderer(
                        mesh: .expanded(frame.mesh), device: device, referenceBounds: first.restBounds)
                    independent.camera = camera
                    independent.animationGroundOffset = nil
                    XCTAssertEqual(
                        actual, try pixels(independent, device: device),
                        "\(family) replacement must draw exactly the independently uploaded posed mesh")
                    for index in stride(from: 0, to: actual.count, by: 4) {
                        let before = initialPixels[index + 3] != 0
                        let after = actual[index + 3] != 0
                        if before != after { changedSilhouettePixels += 1 }
                        if (before || after) && actual[index..<(index + 4)] != initialPixels[index..<(index + 4)] {
                            changedForegroundPixels += 1
                        }
                    }
                }
                try renderer.replaceAnimationFrame(mesh: first.mesh, groundOffset: first.groundOffset)
                renderer.animationGroundOffset = nil
                XCTAssertEqual(
                    try pixels(renderer, device: device), initialPixels,
                    "\(family) restoring the same pose must restore the same GPU image")
            }
            XCTAssertGreaterThan(changedForegroundPixels, 0, "\(family) must visibly change in the actual Metal pass")
            XCTAssertGreaterThan(
                changedSilhouettePixels, 0,
                "\(family) must move projected geometry, beyond normal/lighting changes")
            let receipt = XCTAttachment(
                string:
                    "family=\(family) device=\(device.name) foregroundChanges=\(changedForegroundPixels) silhouetteChanges=\(changedSilhouettePixels) ground=disabled resolution=256x256"
            )
            receipt.lifetime = .keepAlways
            add(receipt)
        }

        private func foregroundCount(_ pixels: [UInt8]) -> Int {
            stride(from: 3, to: pixels.count, by: 4).filter { pixels[$0] != 0 }.count
        }

        private func pixels(_ renderer: MeshRenderer, device: MTLDevice) throws -> [UInt8] {
            let width = 256
            let height = 256
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
            XCTAssertEqual(
                command.status, .completed, command.error?.localizedDescription ?? "GPU pass did not complete")
            return Array(
                UnsafeBufferPointer(
                    start: destination.contents().assumingMemoryBound(to: UInt8.self), count: rowBytes * height))
        }
    }
#endif
