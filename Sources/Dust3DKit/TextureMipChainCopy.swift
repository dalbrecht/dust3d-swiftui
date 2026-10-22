import Dust3DEngine
import Foundation

/// Synchronous C-buffer boundary. The caller keeps the opaque owner alive throughout this operation.
enum TextureMipChainCopy {
    static func copy(
        count: Int, required: Bool, maximumSamplingLod: Double,
        nativeRemaining: inout Int, budget: inout SourceBakeCopyBudget,
        view: (Int) throws -> Dust3DTextureView
    ) throws -> TextureMipChain? {
        try Task.checkCancellation()
        guard count >= 0, count <= 14, count > 0 || !required else {
            throw TextureMipChainError.invalidLevelCount
        }
        if count == 0 { return nil }
        try TextureMipChain.validateLod(maximumSamplingLod, count: count)
        try budget.charge(1, width: MemoryLayout<TextureMipChain>.stride)
        try budget.charge(count, width: MemoryLayout<MeshTextureImage>.stride)
        var levels: [MeshTextureImage] = []
        levels.reserveCapacity(count)
        try budget.charge(levels.capacity - count, width: MemoryLayout<MeshTextureImage>.stride)
        for index in 0..<count {
            try Task.checkCancellation()
            let borrowed = try view(index)
            try Task.checkCancellation()
            try TextureMipChain.validateImage(
                width: borrowed.width, height: borrowed.height, stride: borrowed.row_stride, bytes: borrowed.byte_count)
            try TextureMipChain.validateDimensions(
                width: borrowed.width, height: borrowed.height, previous: levels.last)
            levels.append(try image(borrowed, nativeRemaining: &nativeRemaining, budget: &budget))
        }
        try Task.checkCancellation()
        return try TextureMipChain(levels: levels, maximumSamplingLod: maximumSamplingLod)
    }

    static func image(
        _ borrowed: Dust3DTextureView, nativeRemaining: inout Int, budget: inout SourceBakeCopyBudget
    ) throws -> MeshTextureImage {
        try Task.checkCancellation()
        try TextureMipChain.validateImage(
            width: borrowed.width, height: borrowed.height, stride: borrowed.row_stride, bytes: borrowed.byte_count)
        guard let pixels = borrowed.pixels, borrowed.byte_count <= nativeRemaining else {
            throw TextureMipChainError.invalidImage
        }
        try budget.charge(borrowed.byte_count)
        nativeRemaining -= borrowed.byte_count
        let owned = MeshTextureImage(
            width: borrowed.width, height: borrowed.height, rowStride: borrowed.row_stride,
            pixels: Data(bytes: pixels, count: borrowed.byte_count))
        try Task.checkCancellation()
        return owned
    }

}
