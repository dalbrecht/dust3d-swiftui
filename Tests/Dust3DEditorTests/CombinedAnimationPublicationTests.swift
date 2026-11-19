import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

@testable import Dust3DEditor

@MainActor
final class CombinedAnimationPublicationTests: XCTestCase {
    func testPublishesSuppliedModelAndAudibleSidecarInOrder() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = folder.appendingPathComponent("Fish.fbx")
        let plan = try plan()
        let receipt = await CombinedAnimationPublication.save(
            plan: plan, modelDestination: model, sourceURL: nil, isCurrent: { true },
            encodeModel: { Data([1]) },
            encodeWav: { $0.surface == "Stone" ? nil : Data([2]) })
        let water = folder.appendingPathComponent("Fish_Swim_Water.wav")
        XCTAssertEqual(receipt.published, [model, water])
        XCTAssertEqual(receipt.silent, ["Fish_Swim_Stone.wav"])
        XCTAssertNil(receipt.failure)
        XCTAssertEqual(try Data(contentsOf: model), Data([1]))
        XCTAssertEqual(try Data(contentsOf: water), Data([2]))
    }

    func testLateCollisionPreservesBothOriginalAndPartialReceipt() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = folder.appendingPathComponent("Fish.glb")
        let plan = try plan()
        let existing = folder.appendingPathComponent("Fish_Swim_Water.wav")
        let receipt = await CombinedAnimationPublication.save(
            plan: plan, modelDestination: model, sourceURL: nil, isCurrent: { true },
            encodeModel: { Data([1]) },
            encodeWav: { output in
                if output.surface == "Water" { try Data([9]).write(to: existing) }
                return Data([2])
            })
        XCTAssertEqual(receipt.published, [model, folder.appendingPathComponent("Fish_Swim_Stone.wav")])
        XCTAssertEqual(receipt.failure?.destination, existing)
        XCTAssertEqual(try Data(contentsOf: existing), Data([9]))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 3)
    }

    func testRetiredSourceCannotPublishAfterEncoding() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = folder.appendingPathComponent("Fish.fbx")
        var current = true
        let receipt = await CombinedAnimationPublication.save(
            plan: try plan(), modelDestination: model, sourceURL: nil, isCurrent: { current },
            encodeModel: { Data([1]) },
            encodeWav: { _ in
                current = false
                return Data([2])
            })
        XCTAssertEqual(receipt.published, [model])
        XCTAssertNotNil(receipt.failure?.cause as? CancellationError)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["Fish.fbx"])
    }

    func testExistingSidecarRejectsBeforeEncodingModel() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = folder.appendingPathComponent("Fish.fbx")
        let existing = folder.appendingPathComponent("Fish_Swim_Stone.wav")
        try Data([9]).write(to: existing)
        let receipt = await CombinedAnimationPublication.save(
            plan: try plan(), modelDestination: model, sourceURL: nil, isCurrent: { true },
            encodeModel: {
                XCTFail("Preflight collision must prevent model encoding")
                return Data()
            },
            encodeWav: { _ in nil })
        XCTAssertTrue(receipt.published.isEmpty)
        XCTAssertEqual(receipt.failure?.destination, existing)
        XCTAssertEqual(try Data(contentsOf: existing), Data([9]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: model.path))
    }

    func testFishIdleExportLoadsOncePerClipAndPreservesSurfaceOrder() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = folder.appendingPathComponent("Fish.fbx")
        let (plan, sources) = try await fishIdlePlan()
        var loaded: [String] = []
        var encoded: [Int16] = []
        let receipt = await CombinedAnimationPublication.saveFishIdle(
            plan: plan, sources: sources, modelDestination: model, sourceURL: nil, isCurrent: { true },
            encodeAnimatedModel: { rig, animations in
                XCTAssertEqual(rig, sources[0].playbackRequest.rig)
                XCTAssertEqual(animations.map(\.id), ["a", "b"])
                XCTAssertEqual(animations.map(\.type), ["FishIdle", "FishSwim"])
                return Data([1])
            },
            loadSurfaces: { source, names in
                let id = source.playbackRequest.animation.id
                loaded.append(id)
                return SuppliedFishIdleSurfaceBatch(
                    source: source,
                    tracks: names.enumerated().map { index, name in
                        .init(name: name, samples: index == 0 ? [] : [id == "a" ? 2 : 3])
                    })
            },
            encodeWav: { samples in
                encoded.append(samples[0])
                return Data([UInt8(samples[0])])
            })
        XCTAssertNil(receipt.failure)
        XCTAssertEqual(loaded, ["a", "b"])
        XCTAssertEqual(encoded, [2, 3])
        XCTAssertEqual(
            receipt.published.map(\.lastPathComponent), ["Fish.fbx", "Fish_A_Water.wav", "Fish_B_Water.wav"])
        XCTAssertEqual(receipt.silent, ["Fish_A_Stone.wav", "Fish_B_Stone.wav"])
    }

    func testFishIdleExportRejectsForeignSourceBeforeModelEncoding() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = folder.appendingPathComponent("Fish.fbx")
        let (plan, sources) = try await fishIdlePlan()
        let (_, foreign) = try await fishIdlePlan()
        let receipt = await CombinedAnimationPublication.saveFishIdle(
            plan: plan, sources: [sources[0], foreign[1]], modelDestination: model, sourceURL: nil,
            isCurrent: { true },
            encodeAnimatedModel: { _, _ in
                XCTFail("Foreign clip must reject before model encoding")
                return Data()
            },
            loadSurfaces: { _, _ in throw CancellationError() },
            encodeWav: { _ in throw CancellationError() })
        XCTAssertTrue(receipt.published.isEmpty)
        XCTAssertEqual(receipt.failure?.cause as? FishIdleCopyError, .sourceMismatch)
    }

    func testFishIdleExportRejectsMismatchedBatchBeforeEncodingWav() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = folder.appendingPathComponent("Fish.fbx")
        let (plan, sources) = try await fishIdlePlan()
        let receipt = await CombinedAnimationPublication.saveFishIdle(
            plan: plan, sources: sources, modelDestination: model, sourceURL: nil, isCurrent: { true },
            encodeAnimatedModel: { _, _ in Data([1]) },
            loadSurfaces: { source, names in
                .init(source: source, tracks: names.reversed().map { .init(name: $0, samples: [1]) })
            },
            encodeWav: { _ in
                XCTFail("Mismatched surface order must not encode a WAV")
                return Data()
            })
        XCTAssertEqual(receipt.published, [model])
        XCTAssertEqual(receipt.failure?.cause as? FishIdleCopyError, .nativeReceipt)
    }

    func testCombinedTargetCapturesOnlySupportedClipsFromAcceptedVersion() async throws {
        let fileIdentity = UUID()
        let surfaces = ["Stone", "Wood", "Sand", "Metal", "Grass", "Water", "Dirt", "Snow"]
        func snapshot(type: String, rig: String = "Fish") async throws -> EditorSnapshot {
            let document = try Dust3DDocument(
                snapshotXML: Data(
                    "<canvas rigType='\(rig)'><animations><animation id='a' type='\(type)'/></animations></canvas>".utf8
                ))
            return try await EditorSession().open(data: document.encoded())
        }
        let source = try await snapshot(type: "FishIdle")
        let target = try CombinedFishIdleExportTarget(snapshot: source, fileIdentity: fileIdentity, surfaces: surfaces)
        XCTAssertTrue(target.matches(source, fileIdentity: fileIdentity))
        XCTAssertFalse(target.matches(source, fileIdentity: UUID()))
        let foreign = try await snapshot(type: "FishIdle")
        XCTAssertFalse(target.matches(foreign, fileIdentity: fileIdentity))
        XCTAssertEqual(try target.plan(modelName: "Fish").outputs.map(\.surface), surfaces)
        let legacy = try await snapshot(type: "FishForward")
        let legacyTarget = try CombinedFishIdleExportTarget(
            snapshot: legacy, fileIdentity: fileIdentity, surfaces: surfaces)
        XCTAssertTrue(legacyTarget.matches(legacy, fileIdentity: fileIdentity))
        let snake = try await snapshot(type: "SnakeForward", rig: "Snake")
        let snakeTarget = try CombinedFishIdleExportTarget(
            snapshot: snake, fileIdentity: fileIdentity, surfaces: surfaces)
        XCTAssertTrue(snakeTarget.matches(snake, fileIdentity: fileIdentity))
        let wrongRig = try await snapshot(type: "SnakeForward")
        XCTAssertThrowsError(
            try CombinedFishIdleExportTarget(snapshot: wrongRig, fileIdentity: fileIdentity, surfaces: surfaces))
        let spider = try await snapshot(type: "SpiderRunBackwardRight", rig: "Spider")
        let spiderTarget = try CombinedFishIdleExportTarget(
            snapshot: spider, fileIdentity: fileIdentity, surfaces: surfaces)
        XCTAssertTrue(spiderTarget.matches(spider, fileIdentity: fileIdentity))
        let unsupportedSpider = try await snapshot(type: "SpiderRunForward", rig: "Spider")
        XCTAssertThrowsError(
            try CombinedFishIdleExportTarget(
                snapshot: unsupportedSpider, fileIdentity: fileIdentity, surfaces: surfaces))
        let unsupported = try await snapshot(type: "FishDash")
        XCTAssertThrowsError(
            try CombinedFishIdleExportTarget(snapshot: unsupported, fileIdentity: fileIdentity, surfaces: surfaces))
    }

    func testInsectClipAdmissionUsesExactPinnedNamesAndRig() {
        let base = [
            "InsectAttack", "InsectBite", "InsectDie", "InsectFly", "InsectHurt",
            "InsectIdle", "InsectRubHands", "InsectWalk", "InsectForward",
        ]
        let directions = ["Left", "Right", "Backward", "ForwardLeft", "ForwardRight", "BackwardLeft", "BackwardRight"]
        for type in base + directions.map({ "InsectWalk" + $0 }) {
            XCTAssertTrue(FishIdleCopyReceipt.supportsClipType(type, rigType: "Insect"), type)
            XCTAssertFalse(FishIdleCopyReceipt.supportsClipType(type, rigType: "Spider"), type)
        }
        XCTAssertFalse(FishIdleCopyReceipt.supportsClipType("InsectFlyLeft", rigType: "Insect"))
    }

    func testBirdClipAdmissionUsesExactPinnedNamesAndRig() {
        let base = [
            "BirdAttack", "BirdDie", "BirdEat", "BirdFly", "BirdGlide", "BirdHurt",
            "BirdIdle", "BirdRun", "BirdStrike", "BirdWalk", "BirdForward",
        ]
        let directions = ["Left", "Right", "Backward", "ForwardLeft", "ForwardRight", "BackwardLeft", "BackwardRight"]
        let directional = ["BirdWalk", "BirdRun"].flatMap { gait in directions.map { gait + $0 } }
        for type in base + directional {
            XCTAssertTrue(FishIdleCopyReceipt.supportsClipType(type, rigType: "Bird"), type)
            XCTAssertFalse(FishIdleCopyReceipt.supportsClipType(type, rigType: "Insect"), type)
        }
        XCTAssertFalse(FishIdleCopyReceipt.supportsClipType("BirdGlideLeft", rigType: "Bird"))
    }

    func testQuadrupedClipAdmissionUsesExactPinnedNamesAndRig() {
        let base = [
            "QuadrupedAttack", "QuadrupedDie", "QuadrupedEat", "QuadrupedHurt",
            "QuadrupedIdle", "QuadrupedRoar", "QuadrupedRun", "QuadrupedWalk",
        ]
        let directions = ["Left", "Right", "Backward", "ForwardLeft", "ForwardRight", "BackwardLeft", "BackwardRight"]
        let directional = ["QuadrupedWalk", "QuadrupedRun"].flatMap { gait in directions.map { gait + $0 } }
        for type in base + directional {
            XCTAssertTrue(FishIdleCopyReceipt.supportsClipType(type, rigType: "Quadruped"), type)
            XCTAssertFalse(FishIdleCopyReceipt.supportsClipType(type, rigType: "Bird"), type)
        }
        XCTAssertFalse(FishIdleCopyReceipt.supportsClipType("QuadrupedEatLeft", rigType: "Quadruped"))
    }

    func testBipedClipAdmissionUsesExactPinnedNamesAndRig() {
        for type in ["BipedJump", "BipedCrouchEnter", "BipedSprint", "BipedWalkForwardRight", "BipedRunRight"] {
            XCTAssertTrue(FishIdleCopyReceipt.supportsClipType(type, rigType: "Biped"), type)
            XCTAssertFalse(FishIdleCopyReceipt.supportsClipType(type, rigType: "Quadruped"), type)
        }
        XCTAssertFalse(FishIdleCopyReceipt.supportsClipType("BipedWalkRight", rigType: "Biped"))
    }

    private func fishIdlePlan() async throws -> (CombinedAnimationExportPlan, [SuppliedAnimationSource]) {
        let document = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas rigType='Fish'><animations>
                  <animation id='a' name='A' type='FishIdle'/>
                  <animation id='b' name='B' type='FishSwim'/>
                </animations></canvas>
                """.utf8))
        let snapshot = try await EditorSession().open(data: document.encoded())
        let animations = try document.animations()
        let file = UUID()
        let query = UUID()
        let rig = GeneratedRigPreviewRequest(snapshot: snapshot)
        let sources = animations.map {
            SuppliedAnimationSource(
                playbackRequest: .init(fileIdentity: file, rig: rig, animation: $0, queryID: query),
                rigRevision: UUID())
        }
        return (
            try CombinedAnimationExportPlan(
                modelName: "Fish", animations: animations, surfaces: ["Stone", "Water"]), sources
        )
    }

    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func plan() throws -> CombinedAnimationExportPlan {
        let document = try Dust3DDocument(
            snapshotXML: Data("<canvas><animations><animation id='a' name='Swim'/></animations></canvas>".utf8))
        return try CombinedAnimationExportPlan(
            modelName: "Fish", animations: document.animations(), surfaces: ["Stone", "Water"])
    }
}
