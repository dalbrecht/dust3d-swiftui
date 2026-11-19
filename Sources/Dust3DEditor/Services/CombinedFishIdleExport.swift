import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import Foundation

extension CombinedAnimationPublication {
    /// Binds the supplied animated-model writer and the per-clip audio loader to one captured document.
    static func saveFishIdle(
        plan: CombinedAnimationExportPlan, sources: [SuppliedAnimationSource],
        modelDestination: URL, sourceURL: URL?, isCurrent: () -> Bool,
        encodeAnimatedModel: (GeneratedRigPreviewRequest, [DocumentAnimation]) async throws -> Data,
        loadSurfaces: (SuppliedAnimationSource, [String]) async throws -> SuppliedFishIdleSurfaceBatch,
        encodeWav: ([Int16]) async throws -> Data
    ) async -> Receipt {
        guard let first = sources.first?.playbackRequest, !plan.outputs.isEmpty else {
            return Receipt(failure: Failure(destination: modelDestination, cause: FishIdleCopyError.sourceMismatch))
        }
        var byID: [Data: SuppliedAnimationSource] = [:]
        for source in sources {
            let request = source.playbackRequest
            guard request.rig == first.rig, request.fileIdentity == first.fileIdentity,
                FishIdleCopyReceipt.supportsClipType(request.animation.type, rigType: request.rig.sourceType),
                byID.updateValue(source, forKey: Data(request.animation.id.utf8)) == nil
            else {
                return Receipt(failure: Failure(destination: modelDestination, cause: FishIdleCopyError.sourceMismatch))
            }
        }
        let plannedIDs = Set(plan.outputs.map { Data($0.animation.id.utf8) })
        guard plannedIDs == Set(byID.keys),
            plan.outputs.allSatisfy({ byID[Data($0.animation.id.utf8)]?.playbackRequest.animation == $0.animation })
        else {
            return Receipt(failure: Failure(destination: modelDestination, cause: FishIdleCopyError.sourceMismatch))
        }

        let firstID = plan.outputs.first.map { Data($0.animation.id.utf8) }
        let surfaces = plan.outputs.prefix { Data($0.animation.id.utf8) == firstID }.map(\.surface)
        let animations = stride(from: 0, to: plan.outputs.count, by: surfaces.count).map { plan.outputs[$0].animation }
        var batch: SuppliedFishIdleSurfaceBatch?
        return await save(
            plan: plan, modelDestination: modelDestination, sourceURL: sourceURL, isCurrent: isCurrent,
            encodeModel: { try await encodeAnimatedModel(first.rig, animations) },
            encodeWav: { output in
                guard let source = byID[Data(output.animation.id.utf8)] else { throw FishIdleCopyError.sourceMismatch }
                if batch?.source != source {
                    batch = nil
                    let loaded = try await loadSurfaces(source, surfaces)
                    try Task.checkCancellation()
                    guard isCurrent() else { throw CancellationError() }
                    guard loaded.source == source, loaded.tracks.count == surfaces.count,
                        zip(loaded.tracks, surfaces).allSatisfy({ $0.name.utf8.elementsEqual($1.utf8) })
                    else { throw FishIdleCopyError.nativeReceipt }
                    batch = loaded
                }
                guard let track = batch?.tracks.first(where: { $0.name.utf8.elementsEqual(output.surface.utf8) })
                else { throw FishIdleCopyError.nativeReceipt }
                return track.samples.isEmpty ? nil : try await encodeWav(track.samples)
            })
    }
}

#if MOTE3D_EXPERIMENTAL_FISH_IDLE && MOTE3D_EXPERIMENTAL_GENERATED_RIG
    extension CombinedAnimationPublication {
        static func saveNativeFishIdle(
            plan: CombinedAnimationExportPlan, sources: [SuppliedAnimationSource],
            modelDestination: URL, sourceURL: URL?, isCurrent: () -> Bool, limits: FishIdleCopyLimits
        ) async -> Receipt {
            guard modelDestination.pathExtension.lowercased() == "fbx" else {
                return Receipt(
                    failure: Failure(destination: modelDestination, cause: DocumentExportError.invalidDestination))
            }
            let loader = ExperimentalFishIdleClipService()
            let writer = ExperimentalFishIdleFbxService()
            return await saveFishIdle(
                plan: plan, sources: sources, modelDestination: modelDestination, sourceURL: sourceURL,
                isCurrent: isCurrent,
                encodeAnimatedModel: { rig, animations in
                    try await writer.encode(rig: rig, animations: animations, limits: limits)
                },
                loadSurfaces: { source, surfaces in
                    try await loader.loadSurfaces(source: source, expectedSurfaces: surfaces, limits: limits)
                },
                encodeWav: { samples in
                    let worker = Task.detached { try ExperimentalAnimationWavEncoder.encode(samples) }
                    return try await withTaskCancellationHandler {
                        try await worker.value
                    } onCancel: {
                        worker.cancel()
                    }
                })
        }
    }
#endif
