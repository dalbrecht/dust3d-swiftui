import Dust3DEditorModel

struct SuppliedFishIdleSurfaceBatch: Sendable {
    struct Track: Sendable {
        let name: String
        let samples: [Int16]
    }

    let source: SuppliedAnimationSource
    let tracks: [Track]
}

/// Admit all metadata and both owners' logical payloads before reading any samples.
struct FishIdleSurfaceCopyReceipt {
    struct Row {
        let name: String
        let pcm: FishIdlePCMReceipt
    }

    let selectedAnimationID: String
    let duration: Double
    let nativeVisualBytes: Int
    let nativeSurfaceBytes: Int
    let rows: [Row]

    func copy(
        source: SuppliedAnimationSource, expectedSurfaces: [String], limits: FishIdleCopyLimits,
        readSamples: (Int, Int) throws -> [Int16]
    ) throws -> SuppliedFishIdleSurfaceBatch {
        try Task.checkCancellation()
        let identityBytes = selectedAnimationID.utf8.count
        guard (1...1024).contains(identityBytes),
            selectedAnimationID.utf8.elementsEqual(source.playbackRequest.animation.id.utf8),
            FishIdleCopyReceipt.supportsClipType(
                source.playbackRequest.animation.type, rigType: source.playbackRequest.rig.sourceType)
        else { throw FishIdleCopyError.sourceMismatch }
        guard rows.count == 8, expectedSurfaces.count == rows.count, nativeVisualBytes > 0,
            zip(rows, expectedSurfaces).allSatisfy({
                (1...5).contains($0.name.utf8.count) && $0.name.utf8.elementsEqual($1.utf8)
            })
        else { throw FishIdleCopyError.nativeReceipt }

        let referenceDuration = Float(duration)
        guard (0.001...30).contains(referenceDuration), Double(referenceDuration) == duration,
            let sampleCount = rows.first?.pcm.sampleCount,
            rows.allSatisfy({ row in
                let pcm = row.pcm
                guard pcm.sampleCount == sampleCount else { return false }
                return sampleCount == 0
                    ? pcm.channelCount == 0 && pcm.sampleRate == 0
                    : pcm.admits(duration: duration)
            })
        else { throw FishIdleCopyError.invalidPCM }

        let copiedBytes =
            rows.reduce(0) { $0 + $1.name.utf8.count } + sampleCount * rows.count * MemoryLayout<Int16>.stride
        guard copiedBytes == nativeSurfaceBytes else { throw FishIdleCopyError.nativeReceipt }
        let nativeLimit = min(limits.nativeBytes, limits.combinedBytes, 256 * 1024 * 1024)
        guard nativeLimit >= identityBytes + copiedBytes, nativeVisualBytes <= nativeLimit - identityBytes - copiedBytes
        else { throw FishIdleCopyError.payloadLimit }
        let nativeBytes = identityBytes + nativeVisualBytes + copiedBytes
        guard copiedBytes <= limits.swiftBytes, copiedBytes <= limits.combinedBytes - nativeBytes
        else { throw FishIdleCopyError.payloadLimit }

        let tracks = try rows.enumerated().map { index, row in
            try Task.checkCancellation()
            let samples = sampleCount == 0 ? [] : try readSamples(index, sampleCount)
            guard samples.count == sampleCount else { throw FishIdleCopyError.invalidPCM }
            return SuppliedFishIdleSurfaceBatch.Track(name: row.name, samples: samples)
        }
        try Task.checkCancellation()
        return SuppliedFishIdleSurfaceBatch(source: source, tracks: tracks)
    }
}
