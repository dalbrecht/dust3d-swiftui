import Foundation
import XCTest

@testable import Dust3DKit

final class SourceBakedMipmapsTests: XCTestCase {
    func testRetainsIndependentTypedMapChainsAndEmptyBaseOnlyDefaults() throws {
        let base = MeshTextureImage(width: 2, height: 2, rowStride: 8, pixels: Data(repeating: 255, count: 16))
        let tip = MeshTextureImage(width: 1, height: 1, rowStride: 4, pixels: Data([10, 20, 30, 40]))
        let chain = try TextureMipChain(levels: [base, tip], maximumSamplingLod: 1)
        let empty = SourceBakedMipmaps()
        XCTAssertNil(empty.color)
        XCTAssertNil(empty.normal)
        XCTAssertNil(empty.metallic)
        XCTAssertNil(empty.roughness)
        XCTAssertNil(empty.emissive)
        let maps = SourceBakedMipmaps(color: chain, normal: chain, metallic: chain, roughness: chain, emissive: chain)
        for retained in [maps.color, maps.normal, maps.metallic, maps.roughness, maps.emissive] {
            XCTAssertEqual(retained, chain)
        }
    }
}
