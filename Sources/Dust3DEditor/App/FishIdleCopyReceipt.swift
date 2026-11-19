import Dust3DEditorModel
import Dust3DKit

struct FishIdleCopyLimits: Sendable {
    let nativeBytes: Int
    let swiftBytes: Int
    let combinedBytes: Int
}

enum FishIdleCopyError: Error, Equatable {
    case sourceMismatch, counts, nativeReceipt, payloadLimit, restReceipt, invalidMatrix, invalidPCM
    case invalidGroundMotion
}

struct FishIdlePCMReceipt: Sendable {
    let sampleRate: Int
    let channelCount: Int
    let sampleCount: Int

    func admits(duration: Double) -> Bool {
        let referenceDuration = Float(duration)
        return sampleRate == AnimationPCMPlayback.sampleRate && channelCount == 1
            && (1...AnimationPCMPlayback.maximumSampleCount).contains(sampleCount)
            && (0.001...30).contains(referenceDuration) && Double(referenceDuration) == duration
            && sampleCount == Int(referenceDuration * Float(AnimationPCMPlayback.sampleRate))
    }
}

struct FishIdleGroundMotionReceipt: Sendable {
    let speed: Float
    let directionX: Float
    let directionZ: Float
}

/// Scalar receipt for one co-owned animation clip draw mesh, poses, and optional PCM.
/// Readers must refer to that same owner and enforce the admitted rest counts
/// before copying its buffers. The limits cover logical payload, excluding
/// allocator overhead, source archive storage and native evaluation workspace.
struct FishIdleCopyReceipt: Sendable {
    let selectedAnimationID: String
    let clipType: String
    let duration: Double
    let loops: UInt32
    let warningByteCount: Int
    let vertexCount: Int
    let jointCount: Int
    let frameCount: Int
    let matrixCount: Int
    let nativeRestBytes: Int
    let nativeOutputBytes: Int
    var pcm: FishIdlePCMReceipt? = nil
    var groundMotion: FishIdleGroundMotionReceipt? = nil

    static func supportsClipType(_ type: String?, rigType: String?) -> Bool {
        guard let contract = clipContract(type) else { return false }
        return contract.rig == rigType
    }

    private static func clipContract(_ type: String?) -> (rig: String, loops: Bool)? {
        switch type {
        case "FishIdle", "FishSwim", "FishForward": ("Fish", true)
        case "FishAttack", "FishHurt", "FishDie": ("Fish", false)
        case "SnakeIdle", "SnakeSlither", "SnakeForward": ("Snake", true)
        case "SnakeHurt", "SnakeStrike", "SnakeDie": ("Snake", false)
        case "SpiderAttack", "SpiderHurt", "SpiderDie": ("Spider", false)
        case "SpiderIdle", "SpiderWalk", "SpiderRun",
            "SpiderWalkLeft", "SpiderWalkRight", "SpiderWalkBackward",
            "SpiderWalkForwardLeft", "SpiderWalkForwardRight", "SpiderWalkBackwardLeft", "SpiderWalkBackwardRight",
            "SpiderRunLeft", "SpiderRunRight", "SpiderRunBackward",
            "SpiderRunForwardLeft", "SpiderRunForwardRight", "SpiderRunBackwardLeft", "SpiderRunBackwardRight":
            ("Spider", true)
        case "InsectAttack", "InsectBite", "InsectDie", "InsectHurt": ("Insect", false)
        case "InsectFly", "InsectForward", "InsectIdle", "InsectRubHands", "InsectWalk",
            "InsectWalkLeft", "InsectWalkRight", "InsectWalkBackward",
            "InsectWalkForwardLeft", "InsectWalkForwardRight", "InsectWalkBackwardLeft", "InsectWalkBackwardRight":
            ("Insect", true)
        case "BirdAttack", "BirdDie", "BirdHurt", "BirdStrike": ("Bird", false)
        case "BirdEat", "BirdFly", "BirdForward", "BirdGlide", "BirdIdle", "BirdWalk", "BirdRun",
            "BirdWalkLeft", "BirdWalkRight", "BirdWalkBackward",
            "BirdWalkForwardLeft", "BirdWalkForwardRight", "BirdWalkBackwardLeft", "BirdWalkBackwardRight",
            "BirdRunLeft", "BirdRunRight", "BirdRunBackward",
            "BirdRunForwardLeft", "BirdRunForwardRight", "BirdRunBackwardLeft", "BirdRunBackwardRight":
            ("Bird", true)
        case "QuadrupedAttack", "QuadrupedDie", "QuadrupedHurt", "QuadrupedRoar": ("Quadruped", false)
        case "QuadrupedEat", "QuadrupedIdle", "QuadrupedWalk", "QuadrupedRun",
            "QuadrupedWalkLeft", "QuadrupedWalkRight", "QuadrupedWalkBackward",
            "QuadrupedWalkForwardLeft", "QuadrupedWalkForwardRight",
            "QuadrupedWalkBackwardLeft", "QuadrupedWalkBackwardRight",
            "QuadrupedRunLeft", "QuadrupedRunRight", "QuadrupedRunBackward",
            "QuadrupedRunForwardLeft", "QuadrupedRunForwardRight",
            "QuadrupedRunBackwardLeft", "QuadrupedRunBackwardRight":
            ("Quadruped", true)
        case "BipedBow", "BipedBowDraw", "BipedBowShot",
            "BipedCast", "BipedCastRecover", "BipedCastRelease",
            "BipedCastStart", "BipedChannelEnter", "BipedChannelExit",
            "BipedChannelInterrupt", "BipedCheer", "BipedClap",
            "BipedCrouchEnter", "BipedCrouchExit", "BipedDie",
            "BipedDodge", "BipedDodgeRoll", "BipedDrink",
            "BipedEat", "BipedGather", "BipedGetUp",
            "BipedHurt", "BipedInteract", "BipedJump",
            "BipedJumpStart", "BipedKick", "BipedKnockdown",
            "BipedLand", "BipedOneHandSlash", "BipedParry",
            "BipedPickUp", "BipedPoint", "BipedRoar",
            "BipedSitDown", "BipedSlam", "BipedSlash",
            "BipedSleepLieDown", "BipedStab", "BipedStandUp",
            "BipedThrow", "BipedTurnLeft", "BipedTurnRight",
            "BipedTwoHandSwing", "BipedWakeUp", "BipedWave":
            ("Biped", false)
        case "BipedBlock", "BipedBowAim", "BipedChannel",
            "BipedChop", "BipedCombatIdle", "BipedCrouchIdle",
            "BipedDance", "BipedFall", "BipedHop",
            "BipedIdle", "BipedMine", "BipedMountedIdle",
            "BipedMountedRide", "BipedRun", "BipedRunBackward",
            "BipedRunBackwardLeft", "BipedRunBackwardRight", "BipedRunForwardLeft",
            "BipedRunForwardRight", "BipedRunLeft", "BipedRunRight",
            "BipedSitIdle", "BipedSleepIdle", "BipedSneak",
            "BipedSprint", "BipedStrafeLeft", "BipedStrafeRight",
            "BipedStunned", "BipedSwimBackward", "BipedSwimForward",
            "BipedSwimIdle", "BipedSwimLeft", "BipedSwimRight",
            "BipedTalk", "BipedWalk", "BipedWalkBackward",
            "BipedWalkBackwardLeft", "BipedWalkBackwardRight", "BipedWalkForwardLeft",
            "BipedWalkForwardRight":
            ("Biped", true)
        default: nil
        }
    }

    func copy(
        source: SuppliedAnimationSource, expectedJointNames: [String], limits: FishIdleCopyLimits,
        copyRest: () throws -> GeneratedRig, readTime: (Int) throws -> Double,
        readMatrix: (Int, Int) throws -> SIMD16<Double>, readPCM: ((Int) throws -> Int16)? = nil
    ) throws -> SuppliedAnimationClip {
        try Task.checkCancellation()
        let identityBytes = selectedAnimationID.utf8.count
        guard (1...1024).contains(identityBytes),
            selectedAnimationID.utf8.elementsEqual(source.playbackRequest.animation.id.utf8),
            let contract = Self.clipContract(clipType),
            contract.rig == source.playbackRequest.rig.sourceType,
            source.playbackRequest.animation.type == clipType
        else { throw FishIdleCopyError.sourceMismatch }
        guard duration.isFinite, duration > 0, loops == (contract.loops ? 1 : 0),
            (3...15_000_000).contains(vertexCount), vertexCount.isMultiple(of: 3),
            (1...256).contains(jointCount), expectedJointNames.count == jointCount,
            (2...5000).contains(frameCount), matrixCount == frameCount * jointCount, matrixCount <= 1_000_000
        else { throw FishIdleCopyError.counts }

        var groundVelocity = SIMD2<Double>.zero
        if let groundMotion {
            guard groundMotion.speed.isFinite, groundMotion.directionX.isFinite, groundMotion.directionZ.isFinite
            else { throw FishIdleCopyError.invalidGroundMotion }
            if groundMotion.speed > 0 {
                groundVelocity =
                    SIMD2(Double(groundMotion.directionX), Double(groundMotion.directionZ)) * Double(groundMotion.speed)
            }
        }

        let pcmCount: Int
        if let pcm {
            guard readPCM != nil, frameCount <= 129, pcm.admits(duration: duration)
            else { throw FishIdleCopyError.invalidPCM }
            pcmCount = pcm.sampleCount
        } else {
            guard readPCM == nil else { throw FishIdleCopyError.invalidPCM }
            pcmCount = 0
        }

        let pcmBytes = pcmCount * MemoryLayout<Int16>.stride
        let matrixBytes = 16 * MemoryLayout<Double>.stride
        let poseBytes = matrixCount * matrixBytes + frameCount * MemoryLayout<Double>.stride
        let nativePoseBytes = poseBytes + clipType.utf8.count
        guard nativeRestBytes > 0, nativeOutputBytes >= nativeRestBytes,
            nativeOutputBytes - nativeRestBytes == nativePoseBytes + pcmBytes,
            warningByteCount >= 0, warningByteCount < nativeRestBytes
        else { throw FishIdleCopyError.nativeReceipt }
        // The existing native describe sizes exclude the separately borrowed ID.
        let nativeLimit = min(limits.nativeBytes, limits.combinedBytes, 256 * 1024 * 1024)
        guard nativePoseBytes <= 64 * 1024 * 1024, nativeLimit >= identityBytes,
            nativeOutputBytes <= nativeLimit - identityBytes
        else { throw FishIdleCopyError.payloadLimit }
        let nativeBytes = nativeOutputBytes + identityBytes

        var nameBytes = 0
        for name in expectedJointNames {
            let count = name.utf8.count
            guard (1...1024).contains(count) else { throw FishIdleCopyError.restReceipt }
            nameBytes += count + 1
        }
        let vertexBytes = MemoryLayout<MeshVertex>.stride + MemoryLayout<GeneratedRigInfluences>.stride
        let jointBytes = MemoryLayout<GeneratedRigJoint>.stride + 2 * matrixBytes
        let swiftBytes =
            vertexCount * vertexBytes + jointCount * jointBytes + nameBytes + warningByteCount + 1 + poseBytes
            + pcmBytes + identityBytes
        guard swiftBytes <= limits.swiftBytes, swiftBytes <= limits.combinedBytes - nativeBytes
        else { throw FishIdleCopyError.payloadLimit }

        let rig = try copyRest()
        try Task.checkCancellation()
        guard rig.mesh.vertices.count == vertexCount, rig.influences.count == vertexCount,
            rig.mesh.warning.utf8.count == warningByteCount, rig.joints.count == jointCount,
            zip(expectedJointNames, rig.joints).allSatisfy({
                $0.utf8.elementsEqual($1.name.utf8) && $1.restWorld.count == 16 && $1.inverseBind.count == 16
            })
        else { throw FishIdleCopyError.restReceipt }
        let sampleTimes = try (0..<frameCount).map { frame in
            try Task.checkCancellation()
            return try readTime(frame)
        }
        var matrices: [Double] = []
        matrices.reserveCapacity(matrixCount * 16)
        for frame in 0..<frameCount {
            for joint in 0..<jointCount {
                try Task.checkCancellation()
                let record = try readMatrix(frame, joint)
                for index in 0..<16 {
                    guard record[index].isFinite else { throw FishIdleCopyError.invalidMatrix }
                    matrices.append(record[index])
                }
            }
        }
        let pcmSamples = try readPCM.map { read in
            try (0..<pcmCount).map { index in
                try Task.checkCancellation()
                return try read(index)
            }
        }
        try Task.checkCancellation()
        return try SuppliedAnimationClip(
            source: source, rig: rig, jointNames: expectedJointNames, sampleTimes: sampleTimes,
            duration: duration, loops: contract.loops, matrices: matrices, pcmSamples: pcmSamples,
            groundVelocity: groundVelocity)
    }
}
