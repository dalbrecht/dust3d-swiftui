import AppKit
import Dust3DDocument
import Dust3DEditorModel
import Dust3DRendering
import Foundation
import SwiftUI
import XCTest

@testable import Dust3DEditor
@testable import Dust3DKit

private actor SuppliedPoseGate {
    private var pending: [Int: CheckedContinuation<Mesh, Never>] = [:]
    private var next = 0

    func skin(_ mesh: Mesh, holdOnlyFirst: Bool = false) async -> Mesh {
        next += 1
        let key = next
        if holdOnlyFirst && key > 1 { return mesh }
        return await withCheckedContinuation { pending[key] = $0 }
    }

    func contains(_ key: Int) -> Bool { pending[key] != nil }

    func finish(_ key: Int, mesh: Mesh) {
        pending.removeValue(forKey: key)?.resume(returning: mesh)
    }
}

private actor SuppliedClipGate {
    private var continuation: CheckedContinuation<SuppliedAnimationClip, Never>?

    var isWaiting: Bool { continuation != nil }

    func wait() async -> SuppliedAnimationClip {
        await withCheckedContinuation { continuation = $0 }
    }

    func finish(_ clip: SuppliedAnimationClip) {
        continuation?.resume(returning: clip)
        continuation = nil
    }
}

private actor SuppliedPoseCounter {
    enum Failure: Error { case skinning }
    private(set) var count = 0

    func skin(_ mesh: Mesh, failFirst: Bool = false) throws -> Mesh {
        count += 1
        if failFirst && count == 1 { throw Failure.skinning }
        return mesh
    }
}

@MainActor
final class SuppliedAnimationPreviewTests: XCTestCase {
    private static let identity: [Double] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]

    private final class SourceBox {
        var value: SuppliedAnimationSource?
        init(_ value: SuppliedAnimationSource) { self.value = value }
    }

    private func source(animationID: String = "fish") async throws -> SuppliedAnimationSource {
        let document = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas rigType='Fish'>
                  <nodes><node id='n' partId='p' x='0' y='0' z='0' radius='.1'/></nodes>
                  <edges/><parts><part id='p'/></parts>
                  <animations>
                    <animation id='fish' type='FishIdle'/>
                    <animation id='other' type='FishSwim'/>
                    <animation id='attack' type='FishAttack'/>
                    <animation id='é' type='FishIdle'/>
                    <animation id='e&#x301;' type='FishIdle'/>
                  </animations>
                </canvas>
                """.utf8))
        let snapshot = try await EditorSession().open(data: document.encoded())
        let request = EditorStore.AnimationPlaybackRequest(
            fileIdentity: UUID(), rig: GeneratedRigPreviewRequest(snapshot: snapshot),
            animation: try XCTUnwrap(document.animations().first { $0.id.utf8.elementsEqual(animationID.utf8) }),
            queryID: UUID())
        return SuppliedAnimationSource(playbackRequest: request, rigRevision: UUID())
    }

    private func rig(jointNames: [String] = ["é"]) -> GeneratedRig {
        let joints = jointNames.map { name in
            GeneratedRigJoint(
                name: name, parentIndex: nil, head: .zero, tail: .zero, capsuleRadius: 0,
                closingAngle: 0, restWorld: Self.identity, inverseBind: Self.identity)
        }
        let vertex = MeshVertex(position: SIMD3(1, 0, 0), normal: SIMD3(0, 1, 0), color: .one)
        let influence = GeneratedRigInfluences(joints: SIMD4(0, .max, .max, .max), weights: SIMD4(1, 0, 0, 0))
        return GeneratedRig(
            mesh: Mesh(vertices: Array(repeating: vertex, count: 3), nodeCount: 1, partCount: 1, warning: ""),
            joints: joints, influences: Array(repeating: influence, count: 3), eyelidsGenerated: false)
    }

    private func clip(
        _ source: SuppliedAnimationSource, jointNames: [String] = ["é"], closingTranslation: Double = 0
    ) throws -> SuppliedAnimationClip {
        var moved = Self.identity
        moved[12] = 4
        var last = Self.identity
        last[12] = closingTranslation
        return try SuppliedAnimationClip(
            source: source, rig: rig(), jointNames: jointNames, sampleTimes: [0, 0.25, 1],
            duration: 1, loops: true, matrices: Self.identity + moved + last)
    }

    private func wait(for key: Int, at gate: SuppliedPoseGate) async throws {
        for _ in 0..<10000 {
            if await gate.contains(key) { return }
            await Task.yield()
        }
        throw CancellationError()
    }

    private func fishReceipt(
        jointCount: Int = 1, matrixCount: Int = 3, outputBytes: Int = 1440, selectedAnimationID: String = "fish"
    ) -> FishIdleCopyReceipt {
        FishIdleCopyReceipt(
            selectedAnimationID: selectedAnimationID, clipType: "FishIdle", duration: 1, loops: 1, warningByteCount: 0,
            vertexCount: 3, jointCount: jointCount, frameCount: 3, matrixCount: matrixCount,
            nativeRestBytes: 1024, nativeOutputBytes: outputBytes)
    }

    func testOneShotFishCopyFinishesAtItsDistinctFinalPose() async throws {
        let source = try await source(animationID: "attack")
        let limits = FishIdleCopyLimits(nativeBytes: 4096, swiftBytes: 4096, combinedBytes: 8192)
        func receipt(loops: UInt32) -> FishIdleCopyReceipt {
            FishIdleCopyReceipt(
                selectedAnimationID: "attack", clipType: "FishAttack", duration: 1, loops: loops, warningByteCount: 0,
                vertexCount: 3, jointCount: 1, frameCount: 3, matrixCount: 3,
                nativeRestBytes: 1024, nativeOutputBytes: 1442)
        }
        XCTAssertThrowsError(
            try receipt(loops: 1).copy(
                source: source, expectedJointNames: ["é"], limits: limits,
                copyRest: {
                    XCTFail("A one-shot clip cannot claim a loop")
                    return self.rig()
                }, readTime: { _ in 0 }, readMatrix: { _, _ in .zero })
        ) { XCTAssertEqual($0 as? FishIdleCopyError, .counts) }
        let clip = try receipt(loops: 0).copy(
            source: source, expectedJointNames: ["é"], limits: limits,
            copyRest: { self.rig() }, readTime: { [0, 0.5, 1][$0] },
            readMatrix: { frame, _ in
                var record = SIMD16<Double>(Self.identity)
                record[12] = Double(frame)
                return record
            })
        let preview = SuppliedAnimationPreview()
        let lease = preview.install(clip)
        await preview.sample(.elapsed(2), lease: lease, currentSource: { source })
        let frame = try XCTUnwrap(preview.frame(lease: lease, currentSource: source))
        XCTAssertTrue(frame.position.isFinished)
        XCTAssertEqual(frame.position.sampleIndex, 2)
        XCTAssertEqual(frame.mesh.vertices[0].position, SIMD3(3, 0, 0))
        XCTAssertNil(
            try preview.audioSamples(atRenderedFrame: 0, maximumFrames: 1, lease: lease, currentSource: source))
    }

    func testFishCopyChecksByteExactSelectedIDAndChargesItsNativeStorage() async throws {
        let source = try await source(animationID: "é")
        let ample = FishIdleCopyLimits(nativeBytes: 4096, swiftBytes: 4096, combinedBytes: 8192)
        let tight = FishIdleCopyLimits(nativeBytes: 1441, swiftBytes: 4096, combinedBytes: 8192)
        for (id, limits, expected) in [
            ("e\u{301}", ample, FishIdleCopyError.sourceMismatch),
            ("é", tight, .payloadLimit),
        ] {
            let receipt = fishReceipt(selectedAnimationID: id)
            XCTAssertThrowsError(
                try receipt.copy(
                    source: source, expectedJointNames: ["é"], limits: limits,
                    copyRest: {
                        XCTFail("Read rest before admitting the selected animation identity")
                        return self.rig()
                    },
                    readTime: { _ in 0 }, readMatrix: { _, _ in .zero })
            ) { XCTAssertEqual($0 as? FishIdleCopyError, expected) }
        }
    }

    func testFishCopyRejectsAnotherSelectedAnimationTypeBeforeReading() async throws {
        let source = try await source(animationID: "other")
        let limits = FishIdleCopyLimits(nativeBytes: 4096, swiftBytes: 4096, combinedBytes: 8192)
        var reads = 0
        XCTAssertThrowsError(
            try fishReceipt(selectedAnimationID: "other").copy(
                source: source, expectedJointNames: ["é"], limits: limits,
                copyRest: {
                    reads += 1
                    return self.rig()
                },
                readTime: {
                    reads += 1
                    return [0, 0.25, 1][$0]
                },
                readMatrix: { _, _ in
                    reads += 1
                    return SIMD16<Double>(Self.identity)
                })
        ) { XCTAssertEqual($0 as? FishIdleCopyError, .sourceMismatch) }
        XCTAssertEqual(reads, 0)
    }

    func testFishCopyRejectsCountsAndCoResidencyBeforeReading() async throws {
        let source = try await source()
        let ample = FishIdleCopyLimits(nativeBytes: 4096, swiftBytes: 4096, combinedBytes: 8192)
        let combinedTight = FishIdleCopyLimits(nativeBytes: 4096, swiftBytes: 4096, combinedBytes: 1440)
        let swiftTight = FishIdleCopyLimits(nativeBytes: 4096, swiftBytes: 1, combinedBytes: 8192)
        let nativeTight = FishIdleCopyLimits(nativeBytes: 1439, swiftBytes: 4096, combinedBytes: 8192)
        for (receipt, limits, cause) in [
            (fishReceipt(matrixCount: .max), ample, FishIdleCopyError.counts),
            (fishReceipt(outputBytes: 1439), ample, .nativeReceipt),
            (fishReceipt(), combinedTight, .payloadLimit),
            (fishReceipt(), swiftTight, .payloadLimit),
            (fishReceipt(), nativeTight, .payloadLimit),
        ] {
            XCTAssertThrowsError(
                try receipt.copy(
                    source: source, expectedJointNames: ["é"], limits: limits,
                    copyRest: {
                        XCTFail("Read rest before admission")
                        return self.rig()
                    },
                    readTime: { _ in
                        XCTFail("Read time before admission")
                        return 0
                    },
                    readMatrix: { _, _ in
                        XCTFail("Read matrix before admission")
                        return .zero
                    })
            ) { XCTAssertEqual($0 as? FishIdleCopyError, cause) }
        }
    }

    func testFishCopyPreservesRecordOrderAndRejectsByteDifferentNames() async throws {
        let source = try await source()
        let limits = FishIdleCopyLimits(nativeBytes: 4096, swiftBytes: 4096, combinedBytes: 8192)
        XCTAssertThrowsError(
            try fishReceipt().copy(
                source: source, expectedJointNames: ["e\u{301}"], limits: limits, copyRest: { self.rig() },
                readTime: { _ in
                    XCTFail("Read time after wrong joint name")
                    return 0
                },
                readMatrix: { _, _ in
                    XCTFail("Read matrix after wrong joint name")
                    return .zero
                })
        ) { XCTAssertEqual($0 as? FishIdleCopyError, .restReceipt) }

        XCTAssertThrowsError(
            try fishReceipt(jointCount: 2, matrixCount: 6, outputBytes: 1824).copy(
                source: source, expectedJointNames: ["é", "Root"], limits: limits,
                copyRest: { self.rig(jointNames: ["Root", "é"]) },
                readTime: { _ in
                    XCTFail("Read time after reordered joints")
                    return 0
                },
                readMatrix: { _, _ in
                    XCTFail("Read matrix after reordered joints")
                    return .zero
                })
        ) { XCTAssertEqual($0 as? FishIdleCopyError, .restReceipt) }

        var frames: [Int] = []
        let clip = try fishReceipt().copy(
            source: source, expectedJointNames: ["é"], limits: limits, copyRest: { self.rig() },
            readTime: { [0, 0.25, 1][$0] },
            readMatrix: { frame, joint in
                XCTAssertEqual(joint, 0)
                frames.append(frame)
                var record = SIMD16<Double>(Self.identity)
                if frame == 1 { record[12] = 4 }
                return record
            })
        XCTAssertEqual(frames, [0, 1, 2])
        let preview = SuppliedAnimationPreview()
        let lease = preview.install(clip)
        await preview.sample(.elapsed(0.5), lease: lease, currentSource: { source })
        XCTAssertEqual(preview.frame(lease: lease, currentSource: source)?.mesh.vertices[0].position, SIMD3(5, 0, 0))
    }

    func testFishCopyProjectsOwnedGroundMotionAndRejectsNonfiniteFieldsBeforeReading() async throws {
        let source = try await source()
        let limits = FishIdleCopyLimits(nativeBytes: 4096, swiftBytes: 4096, combinedBytes: 8192)
        var receipt = fishReceipt()
        receipt.groundMotion = .init(speed: 4, directionX: 0.5, directionZ: -1)
        let clip = try receipt.copy(
            source: source, expectedJointNames: ["é"], limits: limits, copyRest: { self.rig() },
            readTime: { [0, 0.25, 1][$0] }, readMatrix: { _, _ in SIMD16<Double>(Self.identity) })
        let preview = SuppliedAnimationPreview()
        let lease = preview.install(clip)
        await preview.sample(.elapsed(0.5), lease: lease, currentSource: { source })
        XCTAssertEqual(preview.frame(lease: lease, currentSource: source)?.groundOffset, SIMD2(1, -2))

        receipt.groundMotion = .init(speed: 4, directionX: .infinity, directionZ: 0)
        XCTAssertThrowsError(
            try receipt.copy(
                source: source, expectedJointNames: ["é"], limits: limits,
                copyRest: {
                    XCTFail("Read rest before validating ground motion")
                    return self.rig()
                },
                readTime: { _ in 0 }, readMatrix: { _, _ in .zero })
        ) { XCTAssertEqual($0 as? FishIdleCopyError, .invalidGroundMotion) }
    }

    func testFishCopyChecksCancellationBeforeAndDuringRecords() async throws {
        let source = try await source()
        let limits = FishIdleCopyLimits(nativeBytes: 4096, swiftBytes: 4096, combinedBytes: 8192)
        let preCancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            XCTAssertThrowsError(
                try fishReceipt().copy(
                    source: source, expectedJointNames: ["é"], limits: limits,
                    copyRest: {
                        XCTFail("Read cancelled rest")
                        return self.rig()
                    },
                    readTime: { _ in
                        XCTFail("Read cancelled time")
                        return 0
                    },
                    readMatrix: { _, _ in
                        XCTFail("Read cancelled matrix")
                        return .zero
                    })
            ) { XCTAssertTrue($0 is CancellationError) }
        }
        try await preCancelled.value

        let midCopy = Task {
            var records = 0
            XCTAssertThrowsError(
                try fishReceipt().copy(
                    source: source, expectedJointNames: ["é"], limits: limits, copyRest: { self.rig() },
                    readTime: { [0, 0.25, 1][$0] },
                    readMatrix: { _, _ in
                        records += 1
                        withUnsafeCurrentTask { $0?.cancel() }
                        return SIMD16<Double>(Self.identity)
                    })
            ) { XCTAssertTrue($0 is CancellationError) }
            XCTAssertEqual(records, 1)
        }
        try await midCopy.value
    }

    private func audioReceipt(
        rate: Int = 44_100, channels: Int = 1, sampleCount: Int = 441, outputBytes: Int = 2322
    ) -> FishIdleCopyReceipt {
        FishIdleCopyReceipt(
            selectedAnimationID: "fish", clipType: "FishIdle", duration: Double(Float(0.01)), loops: 1,
            warningByteCount: 0,
            vertexCount: 3, jointCount: 1, frameCount: 3, matrixCount: 3,
            nativeRestBytes: 1024, nativeOutputBytes: outputBytes,
            pcm: FishIdlePCMReceipt(sampleRate: rate, channelCount: channels, sampleCount: sampleCount))
    }

    func testFishAudioCopyChecksFormatCountAndBothPCMChargesBeforeReaders() async throws {
        let source = try await source()
        let ample = FishIdleCopyLimits(nativeBytes: 4096, swiftBytes: 4096, combinedBytes: 8192)
        let lowSwift = FishIdleCopyLimits(nativeBytes: 4096, swiftBytes: 1200, combinedBytes: 8192)
        let lowCombined = FishIdleCopyLimits(nativeBytes: 4096, swiftBytes: 4096, combinedBytes: 3300)
        for (receipt, limits, cause) in [
            (audioReceipt(rate: 48_000), ample, FishIdleCopyError.invalidPCM),
            (audioReceipt(channels: 2), ample, .invalidPCM),
            (audioReceipt(sampleCount: .max), ample, .invalidPCM),
            (audioReceipt(outputBytes: 1440), ample, .nativeReceipt),
            (audioReceipt(), lowSwift, .payloadLimit),
            (audioReceipt(), lowCombined, .payloadLimit),
        ] {
            XCTAssertThrowsError(
                try receipt.copy(
                    source: source, expectedJointNames: ["é"], limits: limits,
                    copyRest: {
                        XCTFail("Read rest before admission")
                        return self.rig()
                    },
                    readTime: { _ in
                        XCTFail("Read time before admission")
                        return 0
                    },
                    readMatrix: { _, _ in
                        XCTFail("Read matrix before admission")
                        return .zero
                    },
                    readPCM: { _ in
                        XCTFail("Read PCM before admission")
                        return 0
                    })
            ) { XCTAssertEqual($0 as? FishIdleCopyError, cause) }
        }
    }

    func testOwnedFishPCMDrivesPoseCoalescingAndLoopSeam() async throws {
        let source = try await source()
        let receipt = audioReceipt()
        let limits = FishIdleCopyLimits(nativeBytes: 4096, swiftBytes: 4096, combinedBytes: 8192)
        let clip = try receipt.copy(
            source: source, expectedJointNames: ["é"], limits: limits, copyRest: { self.rig() },
            readTime: { [0, receipt.duration / 4, receipt.duration][$0] },
            readMatrix: { frame, _ in
                var record = SIMD16<Double>(Self.identity)
                if frame == 1 { record[12] = 4 }
                return record
            },
            readPCM: { Int16($0 % 7 - 3) })
        let counter = SuppliedPoseCounter()
        let preview = SuppliedAnimationPreview { rig, pose in
            try await counter.skin(rig.referenceSkinnedMesh(modelFromJoint: pose))
        }
        let lease = preview.install(clip)
        await preview.sample(.renderedAudioFrame(120), lease: lease, currentSource: { source })
        await preview.sample(.renderedAudioFrame(130), lease: lease, currentSource: { source })
        XCTAssertEqual(preview.frame(lease: lease, currentSource: source)?.mesh.vertices[0].position, SIMD3(5, 0, 0))
        XCTAssertEqual(preview.frame(lease: lease, currentSource: source)?.position.seconds, 130.0 / 44_100)
        XCTAssertEqual(preview.frame(lease: lease, currentSource: source)?.playbackPosition.pcmFrameOffset, 130)
        await preview.sample(.scrub(15.0 / 44_100), lease: lease, currentSource: { source })
        XCTAssertEqual(preview.frame(lease: lease, currentSource: source)?.playbackPosition.pcmFrameOffset, 15)
        let count = await counter.count
        XCTAssertEqual(count, 2)
        XCTAssertEqual(
            try preview.audioSamples(atRenderedFrame: 440, maximumFrames: 4, lease: lease, currentSource: source)
                .map(Array.init), [3, -3, -2, -1])

        await preview.sample(.renderedAudioFrame(441), lease: lease, currentSource: { source })
        XCTAssertEqual(preview.frame(lease: lease, currentSource: source)?.position.sampleIndex, 0)
        await preview.sample(.scrub(receipt.duration), lease: lease, currentSource: { source })
        XCTAssertEqual(preview.frame(lease: lease, currentSource: source)?.position.sampleIndex, 2)
        XCTAssertNil(preview.frame(lease: lease, currentSource: source)?.playbackPosition.pcmFrameOffset)
        let silentLease = preview.install(try self.clip(source))
        XCTAssertNil(
            try preview.audioSamples(atRenderedFrame: 0, maximumFrames: 4, lease: lease, currentSource: source))
        let missing = await preview.sample(.renderedAudioFrame(0), lease: silentLease, currentSource: { source })
        XCTAssertThrowsError(try XCTUnwrap(missing).get())
        await preview.sample(.elapsed(0), lease: silentLease, currentSource: { source })
        XCTAssertNotNil(preview.frame(lease: silentLease, currentSource: source))
    }

    func testSurfaceBatchAdmitsOnlyExactCatalogRowsWithinCopyBudget() async throws {
        let source = try await source()
        let names = ["Stone", "Wood", "Sand", "Metal", "Grass", "Water", "Dirt", "Snow"]
        let count = 441
        let rows = names.map {
            FishIdleSurfaceCopyReceipt.Row(
                name: $0, pcm: .init(sampleRate: 44_100, channelCount: 1, sampleCount: count))
        }
        let surfaceBytes = names.reduce(count * names.count * 2) { $0 + $1.utf8.count }
        let receipt = FishIdleSurfaceCopyReceipt(
            selectedAnimationID: source.playbackRequest.animation.id, duration: Double(Float(0.01)),
            nativeVisualBytes: 1024, nativeSurfaceBytes: surfaceBytes, rows: rows)
        let budget = FishIdleCopyLimits(nativeBytes: 32_000, swiftBytes: 32_000, combinedBytes: 64_000)
        let copied = try receipt.copy(source: source, expectedSurfaces: names, limits: budget) { index, count in
            Array(repeating: Int16(index), count: count)
        }
        XCTAssertEqual(copied.source, source)
        XCTAssertEqual(copied.tracks.map(\.name), names)
        XCTAssertEqual(copied.tracks[5].samples, Array(repeating: 5, count: count))

        XCTAssertThrowsError(
            try receipt.copy(source: source, expectedSurfaces: names.reversed(), limits: budget) { _, _ in
                XCTFail("Mismatched catalog must not read samples")
                return []
            }
        ) { XCTAssertEqual($0 as? FishIdleCopyError, .nativeReceipt) }
        XCTAssertThrowsError(
            try receipt.copy(
                source: source, expectedSurfaces: names,
                limits: .init(nativeBytes: 32_000, swiftBytes: surfaceBytes - 1, combinedBytes: 64_000)
            ) { _, _ in
                XCTFail("Oversized receipt must not read samples")
                return []
            }
        ) { XCTAssertEqual($0 as? FishIdleCopyError, .payloadLimit) }
    }

    func testSilentSurfaceBatchDoesNotReadSampleBuffers() async throws {
        let source = try await source()
        let names = ["Stone", "Wood", "Sand", "Metal", "Grass", "Water", "Dirt", "Snow"]
        let receipt = FishIdleSurfaceCopyReceipt(
            selectedAnimationID: source.playbackRequest.animation.id, duration: 1, nativeVisualBytes: 1024,
            nativeSurfaceBytes: names.reduce(0) { $0 + $1.utf8.count },
            rows: names.map { .init(name: $0, pcm: .init(sampleRate: 0, channelCount: 0, sampleCount: 0)) })
        let copied = try receipt.copy(
            source: source, expectedSurfaces: names,
            limits: .init(nativeBytes: 2048, swiftBytes: 128, combinedBytes: 4096)
        ) { _, _ in
            XCTFail("Silent rows have no buffer")
            return []
        }
        XCTAssertEqual(copied.tracks.map(\.name), names)
        XCTAssertTrue(copied.tracks.allSatisfy { $0.samples.isEmpty })
    }

    func testWavCaptureUsesWholePausedClipAndRejectsRetiredSources() async throws {
        let source = try await source()
        let other = try await self.source(animationID: "other")
        let samples = (0..<441).map { Int16($0 - 220) }
        let clip = try SuppliedAnimationClip(
            source: source, rig: rig(), jointNames: ["é"], sampleTimes: [0, 0.005, 0.01],
            duration: 0.01, loops: true, matrices: Self.identity + Self.identity + Self.identity, pcmSamples: samples)
        let preview = SuppliedAnimationPreview()
        let lease = preview.install(clip)
        preview.setPlaybackPaused(true, lease: lease, currentSource: source)
        await preview.sample(.scrub(0.005), lease: lease, currentSource: { source })

        let capture = try XCTUnwrap(preview.captureWav(lease: lease, currentSource: source))
        XCTAssertEqual(capture.samples, samples)
        XCTAssertTrue(preview.canPublishWav(capture, currentSource: source))
        XCTAssertFalse(preview.canPublishWav(capture, currentSource: other))
        XCTAssertNil(preview.captureWav(lease: lease, currentSource: other))

        let silentLease = preview.install(try self.clip(source))
        XCTAssertNil(preview.captureWav(lease: silentLease, currentSource: source))
        XCTAssertFalse(preview.canPublishWav(capture, currentSource: source))
        XCTAssertEqual(capture.samples, samples)
    }

    func testFishPCMReadCancelsWithoutReturningAClip() async throws {
        let source = try await source()
        let receipt = audioReceipt()
        let limits = FishIdleCopyLimits(nativeBytes: 4096, swiftBytes: 4096, combinedBytes: 8192)
        let task = Task {
            var reads = 0
            XCTAssertThrowsError(
                try receipt.copy(
                    source: source, expectedJointNames: ["é"], limits: limits, copyRest: { self.rig() },
                    readTime: { [0, receipt.duration / 4, receipt.duration][$0] },
                    readMatrix: { _, _ in SIMD16<Double>(Self.identity) },
                    readPCM: { _ in
                        reads += 1
                        withUnsafeCurrentTask { $0?.cancel() }
                        return 0
                    })
            ) { XCTAssertTrue($0 is CancellationError) }
            XCTAssertEqual(reads, 1)
        }
        try await task.value
    }

    func testSamplesActualSkinningAndDistinguishesLoopFromTerminalScrub() async throws {
        let source = try await source()
        let preview = SuppliedAnimationPreview()
        let lease = preview.install(try clip(source))
        await preview.sample(.elapsed(0.6), lease: lease, currentSource: { source })
        var frame = try XCTUnwrap(preview.frame(lease: lease, currentSource: source))
        XCTAssertEqual(frame.position.sampleIndex, 1)
        XCTAssertEqual(frame.mesh.vertices[0].position, SIMD3(5, 0, 0))
        await preview.sample(.elapsed(1), lease: lease, currentSource: { source })
        frame = try XCTUnwrap(preview.frame(lease: lease, currentSource: source))
        XCTAssertEqual(frame.position.sampleIndex, 0)
        await preview.sample(.scrub(1), lease: lease, currentSource: { source })
        frame = try XCTUnwrap(preview.frame(lease: lease, currentSource: source))
        XCTAssertEqual(frame.position.sampleIndex, 2)
        XCTAssertEqual(frame.mesh.vertices[0].position, SIMD3(1, 0, 0))
    }

    func testExactJointOrderAndClosingPoseAreRequired() async throws {
        let source = try await source()
        XCTAssertThrowsError(try clip(source, jointNames: ["e\u{301}"]))
        XCTAssertThrowsError(try clip(source, closingTranslation: 1))
    }

    func testSuppliedPlaybackMountsItsViewportInAnOffscreenInspector() async throws {
        let request = try await source().playbackRequest
        let rest = rig()
        let matrices = Self.identity + Self.identity
        let view = ExperimentalAnimationPlaybackView(
            request: request, isCurrent: { true },
            loader: { source, _ in
                try SuppliedAnimationClip(
                    source: source, rig: rest, jointNames: ["é"], sampleTimes: [0, 1], duration: 1,
                    loops: true, matrices: matrices)
            })
        let host = NSHostingView(rootView: view.frame(width: 320, height: 320))
        let window = NSWindow(
            contentRect: .init(x: -10000, y: -10000, width: 320, height: 320),
            styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            window.contentView = nil
            window.close()
        }

        func containsViewport(_ view: NSView) -> Bool {
            view is InteractiveMeshView || view.subviews.contains(where: containsViewport)
        }
        for _ in 0..<100 {
            host.layoutSubtreeIfNeeded()
            if containsViewport(host) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(containsViewport(host))
    }

    func testLateClipLoadCannotReplaceTheCurrentSelection() async throws {
        let source = try await source()
        let current = SourceBox(source)
        let gate = SuppliedClipGate()
        let preview = SuppliedAnimationPreview()
        let staleClip = try clip(source)
        let staleLoad = Task {
            try await preview.load(
                source: source, currentSource: { current.value }, using: { _ in await gate.wait() })
        }
        for _ in 0..<10_000 {
            if await gate.isWaiting { break }
            await Task.yield()
        }
        let isWaiting = await gate.isWaiting
        XCTAssertTrue(isWaiting)
        guard isWaiting else {
            staleLoad.cancel()
            return
        }
        let previous = source.playbackRequest
        let request = EditorStore.AnimationPlaybackRequest(
            fileIdentity: previous.fileIdentity, rig: previous.rig, animation: previous.animation, queryID: UUID())
        let fresh = SuppliedAnimationSource(playbackRequest: request, rigRevision: source.rigRevision)
        current.value = fresh
        let freshClip = try clip(fresh)
        let installed = try await preview.load(
            source: fresh, currentSource: { current.value }, using: { _ in freshClip })
        let lease = try XCTUnwrap(installed)
        await gate.finish(staleClip)
        let obsolete = try await staleLoad.value
        XCTAssertNil(obsolete)
        await preview.sample(.elapsed(0.25), lease: lease, currentSource: { current.value })
        XCTAssertEqual(preview.frame(lease: lease, currentSource: fresh)?.position.sampleIndex, 1)
    }

    func testReplacedClipRejectsHeldFrameAndOldLease() async throws {
        let source = try await source()
        let gate = SuppliedPoseGate()
        let preview = SuppliedAnimationPreview { rig, _ in await gate.skin(rig.mesh) }
        let first = preview.install(try clip(source))
        let previous = Task { await preview.sample(.elapsed(0), lease: first, currentSource: { source }) }
        try await wait(for: 1, at: gate)
        let second = preview.install(try clip(source))
        let current = Task { await preview.sample(.elapsed(0.5), lease: second, currentSource: { source }) }
        try await wait(for: 2, at: gate)
        await gate.finish(2, mesh: rig().mesh)
        _ = await current.value
        await gate.finish(1, mesh: rig().mesh)
        _ = await previous.value
        XCTAssertNil(preview.frame(lease: first, currentSource: source))
        XCTAssertEqual(preview.frame(lease: second, currentSource: source)?.position.sampleIndex, 1)
    }

    func testRepeatedTicksKeepInFlightSampleAndPublishLatestTime() async throws {
        let source = try await source()
        let gate = SuppliedPoseGate()
        let preview = SuppliedAnimationPreview { rig, _ in await gate.skin(rig.mesh, holdOnlyFirst: true) }
        let lease = preview.install(try clip(source))
        let first = Task { await preview.sample(.elapsed(0.01), lease: lease, currentSource: { source }) }
        try await wait(for: 1, at: gate)
        let repeated = await preview.sample(.elapsed(0.2), lease: lease, currentSource: { source })
        XCTAssertNil(repeated)
        XCTAssertNil(preview.frame(lease: lease, currentSource: source))
        await gate.finish(1, mesh: rig().mesh)
        let published = await first.value
        XCTAssertEqual(try published?.get().position.seconds, 0.2)
        XCTAssertEqual(preview.frame(lease: lease, currentSource: source)?.position.seconds, 0.2)
    }

    func testScrubKeepsLatestPCMOffsetWhileTheSamePoseIsInFlight() async throws {
        let source = try await source()
        let gate = SuppliedPoseGate()
        let preview = SuppliedAnimationPreview { rig, _ in await gate.skin(rig.mesh, holdOnlyFirst: true) }
        let clip = try SuppliedAnimationClip(
            source: source, rig: rig(), jointNames: ["é"], sampleTimes: [0, 1],
            duration: 1, loops: true, matrices: Self.identity + Self.identity,
            pcmSamples: .init(repeating: 0, count: 44_100))
        let lease = preview.install(clip)
        let first = Task { await preview.sample(.renderedAudioFrame(5), lease: lease, currentSource: { source }) }
        try await wait(for: 1, at: gate)
        let scrub = await preview.sample(.scrub(15.0 / 44_100), lease: lease, currentSource: { source })
        XCTAssertNil(scrub)
        await gate.finish(1, mesh: rig().mesh)
        let published = await first.value
        let frame = try XCTUnwrap(published).get()
        XCTAssertEqual(frame.position.seconds, 15.0 / 44_100)
        XCTAssertEqual(frame.playbackPosition.pcmFrameOffset, 15)
        XCTAssertEqual(preview.frame(lease: lease, currentSource: source)?.playbackPosition.pcmFrameOffset, 15)
    }

    func testGroundMotionKeepsTravelAcrossLoopsAndUsesTheScrubbedSampleTime() async throws {
        let source = try await source()
        let clip = try SuppliedAnimationClip(
            source: source, rig: rig(), jointNames: ["é"], sampleTimes: [0, 0.25, 1],
            duration: 1, loops: true, matrices: Self.identity + Self.identity + Self.identity,
            pcmSamples: .init(repeating: 0, count: 44_100), groundVelocity: SIMD2(2, -4))
        let preview = SuppliedAnimationPreview()
        let lease = preview.install(clip)

        await preview.sample(.elapsed(2.5), lease: lease, currentSource: { source })
        XCTAssertEqual(preview.frame(lease: lease, currentSource: source)?.groundOffset, SIMD2(5, -10))
        await preview.sample(.renderedAudioFrame(110_250), lease: lease, currentSource: { source })
        XCTAssertEqual(preview.frame(lease: lease, currentSource: source)?.groundOffset, SIMD2(5, -10))
        await preview.sample(.scrub(0.5), lease: lease, currentSource: { source })
        XCTAssertEqual(preview.frame(lease: lease, currentSource: source)?.groundOffset, SIMD2(0.5, -1))
        await preview.sample(.resumedAudioFrame(0, fromSample: 1), lease: lease, currentSource: { source })
        let resumed = try XCTUnwrap(preview.frame(lease: lease, currentSource: source))
        XCTAssertEqual(resumed.position.sampleIndex, 1)
        XCTAssertEqual(resumed.playbackPosition.pcmFrameOffset, 11_025)
        XCTAssertEqual(resumed.groundOffset, SIMD2(0.5, -1))
        let audio = try preview.audioSamples(
            atRenderedFrame: 0, maximumFrames: 2, lease: lease, currentSource: source, resumingAtSample: 1)
        XCTAssertEqual(audio?.startIndex, 11_025)
        await preview.sample(.resumedAudioFrame(33_075, fromSample: 1), lease: lease, currentSource: { source })
        let loop = try XCTUnwrap(preview.frame(lease: lease, currentSource: source))
        XCTAssertEqual(loop.position.sampleIndex, 0)
        XCTAssertEqual(loop.playbackPosition.pcmFrameOffset, 0)
        XCTAssertEqual(loop.groundOffset, SIMD2(2, -4))

        preview.setPlaybackPaused(true, lease: lease, currentSource: source)
        XCTAssertNil(
            try preview.audioSamples(atRenderedFrame: 0, maximumFrames: 2, lease: lease, currentSource: source))
        let clock = try XCTUnwrap(preview.setPlaybackPaused(false, lease: lease, currentSource: source))
        XCTAssertNil(
            try preview.audioSamples(atRenderedFrame: 0, maximumFrames: 2, lease: lease, currentSource: source))
        XCTAssertEqual(
            try preview.audioSamples(
                atRenderedFrame: 0, maximumFrames: 2, lease: lease, currentSource: source, clock: clock)?.count,
            2)
    }

    func testSilentResumePreservesScrubbedPoseAndGroundThroughLoop() async throws {
        let source = try await source()
        let clip = try SuppliedAnimationClip(
            source: source, rig: rig(), jointNames: ["é"], sampleTimes: [0, 0.25, 1],
            duration: 1, loops: true, matrices: Self.identity + Self.identity + Self.identity,
            groundVelocity: SIMD2(2, -4))
        let preview = SuppliedAnimationPreview()
        let lease = preview.install(clip)
        await preview.sample(.scrub(0.5), lease: lease, currentSource: { source })
        await preview.sample(.resumedElapsed(0, fromSample: 1), lease: lease, currentSource: { source })
        let resumed = try XCTUnwrap(preview.frame(lease: lease, currentSource: source))
        XCTAssertEqual(resumed.position.sampleIndex, 1)
        XCTAssertNil(resumed.playbackPosition.pcmFrameOffset)
        XCTAssertEqual(resumed.groundOffset, SIMD2(0.5, -1))
        await preview.sample(.resumedElapsed(0.75, fromSample: 1), lease: lease, currentSource: { source })
        let loop = try XCTUnwrap(preview.frame(lease: lease, currentSource: source))
        XCTAssertEqual(loop.position.sampleIndex, 0)
        XCTAssertEqual(loop.groundOffset, SIMD2(2, -4))
    }

    func testVisibleSampleReusesMeshWhileTimeAdvances() async throws {
        let source = try await source()
        let counter = SuppliedPoseCounter()
        let preview = SuppliedAnimationPreview { rig, _ in try await counter.skin(rig.mesh) }
        let lease = preview.install(try clip(source))
        await preview.sample(.elapsed(0.25), lease: lease, currentSource: { source })
        let repeated = await preview.sample(.elapsed(0.75), lease: lease, currentSource: { source })
        XCTAssertEqual(try repeated?.get().position.seconds, 0.75)
        XCTAssertEqual(preview.frame(lease: lease, currentSource: source)?.position.seconds, 0.75)
        let count = await counter.count
        XCTAssertEqual(count, 1)
    }

    func testFailedSampleDoesNotRetryEveryTick() async throws {
        let source = try await source()
        let counter = SuppliedPoseCounter()
        let preview = SuppliedAnimationPreview { rig, _ in try await counter.skin(rig.mesh, failFirst: true) }
        let lease = preview.install(try clip(source))
        let failed = await preview.sample(.elapsed(0.01), lease: lease, currentSource: { source })
        XCTAssertThrowsError(try XCTUnwrap(failed).get())
        let repeated = await preview.sample(.elapsed(0.2), lease: lease, currentSource: { source })
        XCTAssertNil(repeated)
        let count = await counter.count
        XCTAssertEqual(count, 1)

        let retried = await preview.sample(
            .elapsed(0.2), lease: lease, retryFailedSample: true, currentSource: { source })
        XCTAssertEqual(try retried?.get().position.seconds, 0.2)
        XCTAssertEqual(preview.frame(lease: lease, currentSource: source)?.position.seconds, 0.2)
        let countAfterRetry = await counter.count
        XCTAssertEqual(countAfterRetry, 2)
    }

    func testPauseKeepsDisplayedPoseAndBlocksClockTicksUntilResume() async throws {
        let source = try await source()
        let gate = SuppliedPoseGate()
        let preview = SuppliedAnimationPreview { rig, pose in
            if pose[0][12] == 0 { return rig.mesh }
            return await gate.skin(rig.mesh, holdOnlyFirst: true)
        }
        let lease = preview.install(try clip(source))
        await preview.sample(.elapsed(0), lease: lease, currentSource: { source })
        let pending = Task { await preview.sample(.elapsed(0.25), lease: lease, currentSource: { source }) }
        try await wait(for: 1, at: gate)
        preview.setPlaybackPaused(true, lease: lease, currentSource: source)
        await gate.finish(1, mesh: rig().mesh)
        let obsolete = await pending.value
        XCTAssertNil(obsolete)
        let pausedTick = await preview.sample(.elapsed(0.5), lease: lease, currentSource: { source })
        XCTAssertNil(pausedTick)
        XCTAssertEqual(preview.frame(lease: lease, currentSource: source)?.position.seconds, 0)

        await preview.sample(.scrub(0.125), lease: lease, currentSource: { source })
        XCTAssertEqual(preview.frame(lease: lease, currentSource: source)?.position.seconds, 0.125)
        let clock = try XCTUnwrap(preview.setPlaybackPaused(false, lease: lease, currentSource: source))
        let staleTick = await preview.sample(.elapsed(0.75), lease: lease, currentSource: { source })
        XCTAssertNil(staleTick)
        let resumed = await preview.sample(
            .resumedElapsed(0.25, fromSample: 0), lease: lease, clock: clock, currentSource: { source })
        XCTAssertEqual(try resumed?.get().position.sampleIndex, 1)
    }

    func testPlaybackTicksDoNotStarveSlowSkinningAndNextTickCatchesUp() async throws {
        let source = try await source()
        let gate = SuppliedPoseGate()
        let preview = SuppliedAnimationPreview { rig, _ in await gate.skin(rig.mesh, holdOnlyFirst: true) }
        let lease = preview.install(try clip(source))
        let first = Task { await preview.sample(.elapsed(0), lease: lease, currentSource: { source }) }
        try await wait(for: 1, at: gate)
        let skipped = await preview.sample(.elapsed(0.5), lease: lease, currentSource: { source })
        XCTAssertNil(skipped)
        await gate.finish(1, mesh: rig().mesh)
        let completed = await first.value
        XCTAssertEqual(try completed?.get().position.sampleIndex, 0)
        let caughtUp = await preview.sample(.elapsed(0.75), lease: lease, currentSource: { source })
        XCTAssertEqual(try caughtUp?.get().position.sampleIndex, 1)
        XCTAssertEqual(try caughtUp?.get().position.seconds, 0.75)
    }

    func testPendingPoseKeepsLastFrameAndCannotReplaceItAfterScrubbingBack() async throws {
        let source = try await source()
        let gate = SuppliedPoseGate()
        let preview = SuppliedAnimationPreview { rig, pose in
            if pose[0][12] == 0 { return rig.mesh }
            return await gate.skin(rig.mesh)
        }
        let lease = preview.install(try clip(source))
        await preview.sample(.elapsed(0), lease: lease, currentSource: { source })
        let pending = Task { await preview.sample(.elapsed(0.25), lease: lease, currentSource: { source }) }
        try await wait(for: 1, at: gate)
        XCTAssertEqual(preview.frame(lease: lease, currentSource: source)?.position.sampleIndex, 0)
        await preview.sample(.scrub(0.125), lease: lease, currentSource: { source })
        await gate.finish(1, mesh: rig().mesh)
        let obsolete = await pending.value
        XCTAssertNil(obsolete)
        XCTAssertEqual(preview.frame(lease: lease, currentSource: source)?.position.seconds, 0.125)
    }

    func testNewSampleOfSameClipSupersedesHeldSample() async throws {
        let source = try await source()
        let gate = SuppliedPoseGate()
        let preview = SuppliedAnimationPreview { rig, _ in await gate.skin(rig.mesh) }
        let lease = preview.install(try clip(source))
        let held = Task { await preview.sample(.elapsed(0), lease: lease, currentSource: { source }) }
        try await wait(for: 1, at: gate)
        let current = Task { await preview.sample(.scrub(1), lease: lease, currentSource: { source }) }
        try await wait(for: 2, at: gate)
        await gate.finish(2, mesh: rig().mesh)
        _ = await current.value
        await gate.finish(1, mesh: rig().mesh)
        _ = await held.value
        XCTAssertEqual(preview.frame(lease: lease, currentSource: source)?.position.sampleIndex, 2)
    }

    func testSelectionQueryChangeDuringSkinningPreventsPublication() async throws {
        let source = try await source()
        let current = SourceBox(source)
        let gate = SuppliedPoseGate()
        let preview = SuppliedAnimationPreview { rig, _ in await gate.skin(rig.mesh) }
        let lease = preview.install(try clip(source))
        let held = Task { await preview.sample(.elapsed(0), lease: lease, currentSource: { current.value }) }
        try await wait(for: 1, at: gate)
        let previous = source.playbackRequest
        let fresh = EditorStore.AnimationPlaybackRequest(
            fileIdentity: previous.fileIdentity, rig: previous.rig, animation: previous.animation, queryID: UUID())
        current.value = SuppliedAnimationSource(playbackRequest: fresh, rigRevision: source.rigRevision)
        await gate.finish(1, mesh: rig().mesh)
        _ = await held.value
        XCTAssertNil(preview.frame(lease: lease, currentSource: source))
    }

    func testCancelledCallerCannotPublishHeldFrame() async throws {
        let source = try await source()
        let gate = SuppliedPoseGate()
        let preview = SuppliedAnimationPreview { rig, _ in await gate.skin(rig.mesh) }
        let lease = preview.install(try clip(source))
        let held = Task { await preview.sample(.elapsed(0), lease: lease, currentSource: { source }) }
        try await wait(for: 1, at: gate)
        held.cancel()
        await gate.finish(1, mesh: rig().mesh)
        _ = await held.value
        XCTAssertNil(preview.frame(lease: lease, currentSource: source))
    }
}
