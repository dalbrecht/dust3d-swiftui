#if MOTE3D_EXPERIMENTAL_FISH_IDLE && MOTE3D_EXPERIMENTAL_GENERATED_RIG
    import Dust3DEditorModel
    import Dust3DEngine
    import Foundation

    enum ExperimentalAnimationWavError: LocalizedError {
        case encoderRejected(UInt32)
        case invalidOutput

        var errorDescription: String? {
            switch self {
            case .encoderRejected(let status): "Could not encode animation sound (status \(status))."
            case .invalidOutput: "The WAV encoder returned an invalid audio file."
            }
        }
    }

    extension SuppliedAnimationWavCapture {
        /// Copy the complete admitted clip through the bounded portable PCM encoder.
        nonisolated func encodeWav() throws -> Data {
            try ExperimentalAnimationWavEncoder.encode(samples)
        }
    }

    enum ExperimentalAnimationWavEncoder {
        nonisolated static func encode(_ samples: [Int16]) throws -> Data {
            guard (1...AnimationPCMPlayback.maximumSampleCount).contains(samples.count)
            else { throw ExperimentalAnimationWavError.invalidOutput }
            try Task.checkCancellation()
            return try samples.withUnsafeBufferPointer { input in
                let byteCount = 44 + input.count * MemoryLayout<Int16>.size
                var status = DUST3D_AUDIO_WAV_ENCODING_FAILED
                guard
                    let owner = dust3d_audio_wav_create(
                        input.baseAddress, UInt64(input.count), UInt32(AnimationPCMPlayback.sampleRate), 1,
                        UInt64(byteCount), &status)
                else { throw ExperimentalAnimationWavError.encoderRejected(status.rawValue) }
                defer { dust3d_audio_wav_destroy(owner) }
                guard status == DUST3D_AUDIO_WAV_OK, dust3d_audio_wav_size(owner) == UInt64(byteCount),
                    let bytes = dust3d_audio_wav_bytes(owner)
                else { throw ExperimentalAnimationWavError.invalidOutput }
                try Task.checkCancellation()
                return Data(bytes: bytes, count: byteCount)
            }
        }
    }
#endif
