#if MOTE3D_EXPERIMENTAL_FISH_IDLE && MOTE3D_EXPERIMENTAL_GENERATED_RIG
    import Dust3DEngine
    import Dust3DKit
    import Foundation

    actor ExperimentalFishIdleClipService {
        func load(source: SuppliedAnimationSource, includePCM: Bool, limits: FishIdleCopyLimits) async throws
            -> SuppliedAnimationClip
        {
            try await withSelectedOwner(source: source, limits: limits, selection: .clip(includePCM)) { owner, names in
                try FishIdleCopyReceipt.copyExperimentalOwner(
                    owner, source: source, expectedJointNames: names, limits: limits)
            }
        }

        func loadSurfaces(source: SuppliedAnimationSource, expectedSurfaces: [String], limits: FishIdleCopyLimits)
            async throws -> SuppliedFishIdleSurfaceBatch
        {
            try await withSelectedOwner(source: source, limits: limits, selection: .surfaces) { owner, _ in
                try FishIdleSurfaceCopyReceipt.copyExperimentalOwner(
                    owner, source: source, expectedSurfaces: expectedSurfaces, limits: limits)
            }
        }

        private enum Selection {
            case clip(Bool)
            case surfaces
        }

        private func withSelectedOwner<Result>(
            source: SuppliedAnimationSource, limits: FishIdleCopyLimits, selection: Selection,
            copy: (OpaquePointer, [String]) throws -> Result
        ) async throws -> Result {
            try Task.checkCancellation()
            let request = source.playbackRequest
            guard FishIdleCopyReceipt.supportsClipType(request.animation.type, rigType: request.rig.sourceType),
                let hierarchy = try RigTemplateHierarchy.load(sourceType: request.rig.sourceType)
            else { throw FishIdleCopyError.sourceMismatch }
            let budget = min(limits.nativeBytes, limits.combinedBytes)
            guard budget > 0 else { throw FishIdleCopyError.payloadLimit }

            var error = Dust3DError()
            guard let pointer = dust3d_cancellation_token_create(&error) else { throw MeshLoader.loadingError(error) }
            let token = NativeBakeCancellation(pointer)
            defer { token.close() }
            return try await withTaskCancellationHandler {
                try GeneratedRig.withNativeBones(hierarchy.bones) { bones in
                    try request.rig.archive.withUnsafeBytes { archive in
                        try request.animation.id.utf8CString.withUnsafeBufferPointer { identity in
                            var options = dust3d_experimental_fish_idle_default_options()
                            options.rig.maximum_output_bytes = min(options.rig.maximum_output_bytes, budget)
                            options.rig.head_has_eyelids = request.rig.headHasEyelids ? 1 : 0
                            options.rig.cancellation = pointer
                            let loaded: OpaquePointer?
                            let bytes = archive.bindMemory(to: UInt8.self).baseAddress
                            switch selection {
                            case .clip(let includePCM):
                                loaded = dust3d_experimental_fish_idle_load_selected(
                                    bytes, archive.count, bones.baseAddress, bones.count,
                                    identity.baseAddress, identity.count - 1, includePCM ? 1 : 0, &options, &error)
                            case .surfaces:
                                loaded = dust3d_experimental_fish_idle_load_selected_surfaces(
                                    bytes, archive.count, bones.baseAddress, bones.count,
                                    identity.baseAddress, identity.count - 1, &options, &error)
                            }
                            guard let owner = loaded else {
                                try Task.checkCancellation()
                                throw MeshLoader.loadingError(error)
                            }
                            defer { dust3d_experimental_fish_idle_destroy(owner) }
                            return try copy(owner, hierarchy.bones.map(\.name))
                        }
                    }
                }
            } onCancel: {
                token.cancel()
            }
        }
    }

    extension FishIdleSurfaceCopyReceipt {
        static func copyExperimentalOwner(
            _ owner: OpaquePointer, source: SuppliedAnimationSource, expectedSurfaces: [String],
            limits: FishIdleCopyLimits
        ) throws -> SuppliedFishIdleSurfaceBatch {
            try Task.checkCancellation()
            let count = dust3d_experimental_fish_idle_surface_count(owner)
            var selectedLength = 0
            var visual = Dust3DExperimentalFishIdleInfo()
            guard count == 8,
                let expectedType = source.playbackRequest.animation.type?.utf8,
                let selected = dust3d_experimental_fish_idle_selected_id(owner, &selectedLength),
                (1...1024).contains(selectedLength),
                let selectedID = String(
                    bytes: UnsafeRawBufferPointer(start: selected, count: selectedLength), encoding: .utf8),
                dust3d_experimental_fish_idle_describe(owner, &visual) == 1,
                let type = visual.clip_type, visual.clip_type_length == expectedType.count,
                UnsafeRawBufferPointer(start: type, count: visual.clip_type_length).elementsEqual(expectedType)
            else { throw FishIdleCopyError.nativeReceipt }
            var nativeRows: [Dust3DExperimentalFishIdleSurfacePCMInfo] = []
            let rows = try (0..<count).map { index in
                var row = Dust3DExperimentalFishIdleSurfacePCMInfo()
                guard dust3d_experimental_fish_idle_describe_surface_pcm(owner, index, &row) == 1,
                    let name = row.surface_name, (1...5).contains(row.surface_name_length),
                    let surface = String(
                        bytes: UnsafeRawBufferPointer(start: name, count: row.surface_name_length), encoding: .utf8),
                    (row.samples == nil) == (row.sample_count == 0)
                else { throw FishIdleCopyError.nativeReceipt }
                nativeRows.append(row)
                return Row(
                    name: surface,
                    pcm: .init(
                        sampleRate: Int(row.sample_rate), channelCount: Int(row.channel_count),
                        sampleCount: row.sample_count))
            }
            let receipt = FishIdleSurfaceCopyReceipt(
                selectedAnimationID: selectedID, duration: visual.duration_seconds,
                nativeVisualBytes: visual.output_bytes,
                nativeSurfaceBytes: dust3d_experimental_fish_idle_surface_output_bytes(owner), rows: rows)
            return try receipt.copy(source: source, expectedSurfaces: expectedSurfaces, limits: limits) {
                index, count in
                guard let samples = nativeRows[index].samples else { throw FishIdleCopyError.invalidPCM }
                return Array(UnsafeBufferPointer(start: samples, count: count))
            }
        }
    }

    /// Copies a borrowed private owner synchronously. The caller retains and destroys the owner.
    extension FishIdleCopyReceipt {
        static func copyExperimentalOwner(
            _ owner: OpaquePointer, source: SuppliedAnimationSource, expectedJointNames: [String],
            limits: FishIdleCopyLimits
        ) throws -> SuppliedAnimationClip {
            try Task.checkCancellation()
            var selectedLength = 0
            guard let selected = dust3d_experimental_fish_idle_selected_id(owner, &selectedLength),
                (1...1024).contains(selectedLength),
                let selectedID = String(
                    bytes: UnsafeRawBufferPointer(start: selected, count: selectedLength), encoding: .utf8),
                selectedID.utf8.elementsEqual(source.playbackRequest.animation.id.utf8)
            else { throw FishIdleCopyError.sourceMismatch }

            var info = Dust3DExperimentalFishIdlePCMInfo()
            var motion = Dust3DExperimentalFishIdleGroundMotion()
            guard dust3d_experimental_fish_idle_describe_pcm(owner, &info) == 1,
                dust3d_experimental_fish_idle_ground_motion(owner, &motion) == 1,
                let rest = info.visual.rest,
                let mesh = dust3d_generated_rig_mesh(rest),
                let times = info.visual.sample_times,
                let expectedType = source.playbackRequest.animation.type,
                let type = info.visual.clip_type, info.visual.clip_type_length == expectedType.utf8.count,
                UnsafeRawBufferPointer(start: type, count: info.visual.clip_type_length).elementsEqual(
                    expectedType.utf8)
            else { throw FishIdleCopyError.nativeReceipt }

            let pcm: FishIdlePCMReceipt?
            let readPCM: ((Int) throws -> Int16)?
            if info.sample_count == 0 {
                guard info.sample_rate == 0, info.channel_count == 0 else { throw FishIdleCopyError.invalidPCM }
                pcm = nil
                readPCM = nil
            } else {
                pcm = FishIdlePCMReceipt(
                    sampleRate: Int(info.sample_rate), channelCount: Int(info.channel_count),
                    sampleCount: info.sample_count)
                readPCM = { index in
                    var sample: Int16 = 0
                    guard dust3d_experimental_fish_idle_pcm_at(owner, index, &sample) == 1
                    else { throw FishIdleCopyError.invalidPCM }
                    return sample
                }
            }

            let receipt = FishIdleCopyReceipt(
                selectedAnimationID: selectedID, clipType: expectedType, duration: info.visual.duration_seconds,
                loops: info.visual.loops, warningByteCount: info.visual.warning_length,
                vertexCount: dust3d_mesh_vertex_count(mesh), jointCount: info.visual.joint_count,
                frameCount: info.visual.frame_count, matrixCount: info.visual.matrix_count,
                nativeRestBytes: dust3d_generated_rig_output_bytes(rest), nativeOutputBytes: info.output_bytes,
                pcm: pcm,
                groundMotion: .init(speed: motion.speed, directionX: motion.direction_x, directionZ: motion.direction_z)
            )
            return try receipt.copy(
                source: source, expectedJointNames: expectedJointNames, limits: limits,
                copyRest: { try GeneratedRig.copy(rest, expectedNames: expectedJointNames) },
                readTime: { times[$0] },
                readMatrix: { frame, joint in
                    var matrix = Dust3DExperimentalFishIdleMatrix()
                    guard dust3d_experimental_fish_idle_matrix_at(owner, frame, joint, &matrix) == 1
                    else { throw FishIdleCopyError.invalidMatrix }
                    return withUnsafeBytes(of: matrix.values) { $0.loadUnaligned(as: SIMD16<Double>.self) }
                }, readPCM: readPCM)
        }
    }
#endif
