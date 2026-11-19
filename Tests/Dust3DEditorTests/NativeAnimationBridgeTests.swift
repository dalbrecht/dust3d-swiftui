#if MOTE3D_EXPERIMENTAL_FISH_IDLE && MOTE3D_EXPERIMENTAL_GENERATED_RIG
    import Dust3DDocument
    import Dust3DEditorModel
    import Dust3DKit
    import Foundation
    import XCTest

    @testable import Dust3DEditor

    @MainActor
    final class NativeAnimationBridgeTests: XCTestCase {
        func testAuthoredFishClipsProduceOwnedSkinnedFramesThroughNativeService() async throws {
            let document = try Dust3DDocument(snapshotXML: Data(fishXML.utf8))
            let snapshot = try await EditorSession().open(data: document.encoded())
            let loader = ExperimentalFishIdleClipService()
            for animation in try document.animations() {
                let request = EditorStore.AnimationPlaybackRequest(
                    fileIdentity: UUID(), rig: GeneratedRigPreviewRequest(snapshot: snapshot),
                    animation: animation, queryID: UUID())
                let source = SuppliedAnimationSource(playbackRequest: request, rigRevision: UUID())
                let clip = try await loader.load(
                    source: source, includePCM: true,
                    limits: FishIdleCopyLimits(
                        nativeBytes: 64 * 1024 * 1024, swiftBytes: 64 * 1024 * 1024,
                        combinedBytes: 128 * 1024 * 1024))
                XCTAssertEqual(clip.source, source)
                let preview = SuppliedAnimationPreview()
                let lease = preview.install(clip)
                let result = await preview.sample(.scrub(0.375), lease: lease, currentSource: { source })
                let frame = try XCTUnwrap(result).get()
                XCTAssertEqual(frame.position.sampleIndex, 3)
                XCTAssertEqual(frame.lease, lease)
                XCTAssertFalse(frame.mesh.vertices.isEmpty)
                XCTAssertTrue(
                    frame.mesh.vertices.allSatisfy {
                        $0.position.x.isFinite && $0.position.y.isFinite && $0.position.z.isFinite
                    })
                preview.stop()
            }
        }

        private func identity(_ value: Int) -> String {
            "{00000000-0000-4000-8000-\(String(format: "%012d", value))}"
        }

        private var fishXML: String {
            // Goldfish body chain from Core's generated PCM fixture, including TailEnd.
            let nodes: [(Double, Double, Double)] = [
                (0, 0.36, 0.04), (0.01, 0.28, 0.12), (0.02, 0.12, 0.18),
                (0.02, -0.05, 0.16), (0.02, -0.2, 0.09), (0.02, -0.3, 0.05),
                (0.02, -0.39, 0.025),
            ]
            let bones = ["Head", "BodyFront", "BodyMid", "BodyRear", "TailStart", "TailEnd"]
            let nodeXML = nodes.enumerated().map { index, node in
                "<node id='\(identity(index + 1))' partId='\(identity(100))' x='0' y='\(node.0)' z='\(node.1)' radius='\(node.2)'/>"
            }.joined()
            let edgeXML = bones.enumerated().map { index, bone in
                "<edge id='\(identity(index + 200))' partId='\(identity(100))' from='\(identity(index + 1))' to='\(identity(index + 2))' boneName='\(bone)'/>"
            }.joined()
            return """
                <canvas rigType='Fish' originX='0' originY='0' originZ='0'>
                  <nodes>\(nodeXML)</nodes><edges>\(edgeXML)</edges>
                  <parts><part id='\(identity(100))' target='Model' rounded='false' subdivided='false'/></parts>
                  <components><component id='\(identity(101))' linkDataType='partId' linkData='\(identity(100))'/></components>
                  <animations>
                    <animation id='idle' type='FishIdle' durationSeconds='1' frameCount='8' driftFactor='3' surfaceMaterial='Water'/>
                    <animation id='swim' type='FishSwim' durationSeconds='1' frameCount='8' surfaceMaterial='Water'/>
                  </animations>
                </canvas>
                """
        }
    }
#endif
