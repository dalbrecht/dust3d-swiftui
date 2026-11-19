#if MOTE3D_EXPERIMENTAL_FISH_IDLE && MOTE3D_EXPERIMENTAL_GENERATED_RIG
    import Dust3DDocument
    import Dust3DEngine
    import Dust3DKit
    import Foundation

    actor ExperimentalFishIdleFbxService {
        func encode(rig: GeneratedRigPreviewRequest, animations: [DocumentAnimation], limits: FishIdleCopyLimits)
            async throws -> Data
        {
            try Task.checkCancellation()
            guard (1...128).contains(animations.count),
                let hierarchy = try RigTemplateHierarchy.load(sourceType: rig.sourceType)
            else { throw FishIdleCopyError.sourceMismatch }
            var storage: [CChar] = []
            var offsets: [Range<Int>] = []
            var seen: Set<Data> = []
            for animation in animations {
                let id = animation.id.utf8
                guard FishIdleCopyReceipt.supportsClipType(animation.type, rigType: rig.sourceType),
                    (1...1024).contains(id.count),
                    !id.contains(0),
                    seen.insert(Data(id)).inserted
                else { throw FishIdleCopyError.sourceMismatch }
                let start = storage.count
                storage.append(contentsOf: id.map { CChar(bitPattern: $0) })
                offsets.append(start..<storage.count)
            }
            let outputBudget = FishIdleFbxCopy.outputBudget(limits)
            guard outputBudget > 27 else { throw FishIdleCopyError.payloadLimit }

            var error = Dust3DError()
            guard let pointer = dust3d_cancellation_token_create(&error) else { throw MeshLoader.loadingError(error) }
            let token = NativeBakeCancellation(pointer)
            defer { token.close() }
            return try await withTaskCancellationHandler {
                try GeneratedRig.withNativeBones(hierarchy.bones) { bones in
                    try rig.archive.withUnsafeBytes { archive in
                        try storage.withUnsafeBufferPointer { text in
                            let ids = offsets.map { span in
                                Dust3DExperimentalFishIdleFbxClipID(
                                    id: text.baseAddress?.advanced(by: span.lowerBound), length: span.count)
                            }
                            return try ids.withUnsafeBufferPointer { ids in
                                var options = dust3d_generated_rig_default_options()
                                options.maximum_output_bytes = min(
                                    256 * 1024 * 1024, limits.nativeBytes, limits.combinedBytes)
                                options.head_has_eyelids = rig.headHasEyelids ? 1 : 0
                                options.cancellation = pointer
                                let bakeOptions = MeshBakeOptions(
                                    maximumMetadataPayloadBytes: 32 * 1024 * 1024,
                                    maximumBakePayloadBytes: 128 * 1024 * 1024)
                                let exported = try MeshBakedInput.withArchiveOptions(
                                    archive: rig.archive, options: bakeOptions, cancellation: pointer
                                ) { bake in
                                    dust3d_experimental_fish_idle_fbx_create_baked(
                                        archive.bindMemory(to: UInt8.self).baseAddress, archive.count,
                                        bones.baseAddress, bones.count, ids.baseAddress, ids.count, &options, &bake,
                                        outputBudget, &error)
                                }
                                guard let owner = exported else {
                                    try Task.checkCancellation()
                                    throw MeshLoader.loadingError(error)
                                }
                                defer { dust3d_experimental_fish_idle_fbx_destroy(owner) }
                                return try FishIdleFbxCopy.copy(
                                    byteCount: dust3d_experimental_fish_idle_fbx_size(owner), limits: limits
                                ) { count in
                                    guard let bytes = dust3d_experimental_fish_idle_fbx_bytes(owner)
                                    else { throw FishIdleCopyError.nativeReceipt }
                                    return Data(bytes: bytes, count: count)
                                }
                            }
                        }
                    }
                }
            } onCancel: {
                token.cancel()
            }
        }
    }
#endif
