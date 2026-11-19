#if MOTE3D_EXPERIMENTAL_FISH_IDLE && MOTE3D_EXPERIMENTAL_GENERATED_RIG
    import CryptoKit
    import Dust3DDocument
    import Dust3DEditorModel
    import Dust3DKit
    import Foundation
    import XCTest

    @testable import Dust3DEditor

    @MainActor
    final class NativeAnimationFamilyBridgeTests: XCTestCase {
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

        func testBirdCopiesSkinsAndRetainsSelectedNativeClips() async throws { try await verify("Bird") }
        func testQuadrupedCopiesSkinsAndRetainsSelectedNativeClips() async throws { try await verify("Quadruped") }
        func testBipedCopiesSkinsAndRetainsSelectedNativeClips() async throws { try await verify("Biped") }
        func testFishCopiesSkinsAndRetainsSelectedNativeClips() async throws { try await verify("Fish") }
        func testInsectCopiesSkinsAndRetainsSelectedNativeClips() async throws { try await verify("Insect") }
        func testSnakeCopiesSkinsAndRetainsSelectedNativeClips() async throws { try await verify("Snake") }
        func testSpiderCopiesSkinsAndRetainsSelectedNativeClips() async throws { try await verify("Spider") }

        private func verify(_ family: String) async throws {
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
            let idleSource = try source(fixture.idle)
            let loader = ExperimentalFishIdleClipService()
            let movingClip = try await loader.load(source: movingSource, includePCM: true, limits: limits)
            XCTAssertEqual(movingClip.source, movingSource)
            let preview = SuppliedAnimationPreview()
            defer { preview.stop() }
            let movingLease = preview.install(movingClip)
            XCTAssertEqual(
                preview.previewSampleCount(lease: movingLease, currentSource: movingSource),
                fixture.moving.authoredFrameCount)
            let first = try await sample(preview, source: movingSource, lease: movingLease, seconds: 0)
            XCTAssertFalse(first.mesh.vertices.isEmpty)
            XCTAssertTrue(preview.hasAudio(lease: movingLease, currentSource: movingSource))
            let wav = try XCTUnwrap(preview.captureWav(lease: movingLease, currentSource: movingSource))
            XCTAssertEqual(wav.samples.count, Int(fixture.moving.duration * 44_100))
            XCTAssertTrue(wav.samples.contains { $0 != 0 }, "\(family) moving PCM must contain audible data")
            XCTAssertTrue(preview.canPublishWav(wav, currentSource: movingSource))
            XCTAssertNil(preview.captureWav(lease: movingLease, currentSource: idleSource))
            var deformed = false
            var retained: SuppliedAnimationFrame?
            for fraction in [0.25, 0.5, 0.75] {
                let seconds = fixture.moving.duration * fraction
                let frame = try await sample(preview, source: movingSource, lease: movingLease, seconds: seconds)
                try verifySampleIndex(preview, source: movingSource, lease: movingLease, seconds: seconds, frame: frame)
                verifyMesh(frame.mesh, matches: first.mesh)
                deformed =
                    deformed
                    || zip(first.mesh.vertices, frame.mesh.vertices).contains { before, after in
                        let delta = after.position - before.position
                        return abs(delta.x) > 0.00001 || abs(delta.y) > 0.00001 || abs(delta.z) > 0.00001
                    }
                if fraction == 0.25 { retained = frame }
            }
            XCTAssertTrue(deformed, "\(family) authored moving clip must deform its copied body")

            // The later native generation releases its owners before returning.
            // Reinstall the earlier copied clip to exercise its arrays afresh.
            let idleClip = try await loader.load(source: idleSource, includePCM: true, limits: limits)
            XCTAssertEqual(idleClip.source, idleSource)
            let idleLease = preview.install(idleClip)
            XCTAssertFalse(preview.hasAudio(lease: idleLease, currentSource: idleSource))
            XCTAssertNil(preview.captureWav(lease: idleLease, currentSource: idleSource))
            XCTAssertFalse(preview.canPublishWav(wav, currentSource: movingSource))
            XCTAssertEqual(
                preview.previewSampleCount(lease: idleLease, currentSource: idleSource), fixture.idle.authoredFrameCount
            )
            let idle = try await sample(
                preview, source: idleSource, lease: idleLease, seconds: fixture.idle.duration * 0.25)
            verifyMesh(idle.mesh, matches: first.mesh)
            let reinstalledLease = preview.install(movingClip)
            let replayed = try await sample(
                preview, source: movingSource, lease: reinstalledLease, seconds: fixture.moving.duration * 0.25)
            let expected = try XCTUnwrap(retained)
            XCTAssertEqual(replayed.mesh.vertices.map(\.position), expected.mesh.vertices.map(\.position))
            XCTAssertEqual(replayed.mesh.vertices.map(\.normal), expected.mesh.vertices.map(\.normal))
            XCTAssertEqual(replayed.mesh.vertices.map(\.color), expected.mesh.vertices.map(\.color))
            XCTAssertEqual(
                preview.captureWav(lease: reinstalledLease, currentSource: movingSource)?.samples, wav.samples)
        }

        private func sample(
            _ preview: SuppliedAnimationPreview, source: SuppliedAnimationSource, lease: UUID, seconds: Double
        ) async throws -> SuppliedAnimationFrame {
            let result = await preview.sample(.scrub(seconds), lease: lease, currentSource: { source })
            let frame = try XCTUnwrap(result).get()
            XCTAssertEqual(frame.lease, lease)
            return frame
        }

        private func verifySampleIndex(
            _ preview: SuppliedAnimationPreview, source: SuppliedAnimationSource, lease: UUID, seconds: Double,
            frame: SuppliedAnimationFrame
        ) throws {
            let count = try XCTUnwrap(preview.previewSampleCount(lease: lease, currentSource: source))
            let times = try (0..<count).map {
                try XCTUnwrap(preview.previewSampleTime(at: $0, lease: lease, currentSource: source))
            }
            let expected = try XCTUnwrap(times.lastIndex { $0 <= seconds })
            XCTAssertEqual(frame.position.sampleIndex, expected)
        }

        private func verifyMesh(_ mesh: Mesh, matches original: Mesh) {
            XCTAssertEqual(mesh.vertices.count, original.vertices.count)
            XCTAssertEqual(mesh.nodeCount, original.nodeCount)
            XCTAssertEqual(mesh.partCount, original.partCount)
            XCTAssertEqual(mesh.vertices.map(\.color), original.vertices.map(\.color))
            XCTAssertTrue(
                mesh.vertices.allSatisfy {
                    $0.position.x.isFinite && $0.position.y.isFinite && $0.position.z.isFinite
                        && $0.normal.x.isFinite && $0.normal.y.isFinite && $0.normal.z.isFinite
                })
        }
    }
#endif
