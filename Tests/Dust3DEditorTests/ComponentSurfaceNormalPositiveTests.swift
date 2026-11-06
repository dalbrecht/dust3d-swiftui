import CryptoKit
import Dust3DKit
import XCTest

final class ComponentSurfaceNormalPositiveTests: XCTestCase {
    private enum FixtureError: Error { case unreviewedInput }

    func testReviewedClothInputsProduceActualGeneratedNormalMapAtProductionPin() async throws {
        let baker = ArchiveSourceTextureBakingService()
        let options = SourceMeshBakeOptions(
            bake: MeshBakeOptions(colorSize: 256, normalSize: 256, materialSize: 64, atlasTextureSize: 256))
        for wrinkles in [false, true] {
            let source = try SurfaceDetailPositiveFixture.cloth(wrinkles: wrinkles)
            let digest = SHA256.hash(data: source).map { String(format: "%02x", $0) }.joined()
            let expected =
                wrinkles
                ? "7dc60d1b168bc2de2436d313dc08b26fc884dc4d63b9bac14e40a47240373bc4"
                : "f903aa81e67b5d0a11c99586f8edb288b5df0d9c694a1d7e5de5aac392aae585"
            guard source.count == 684, digest == expected else {
                XCTFail("Fixture bytes are outside the reviewed native-input scope")
                throw FixtureError.unreviewedInput
            }
            let result = try await baker.load(data: source, options: options)
            XCTAssertGreaterThan(result.geometry.triangleCount, 0)
            XCTAssertTrue(
                result.geometry.vertices.allSatisfy {
                    $0.position.x.isFinite && $0.position.y.isFinite && $0.position.z.isFinite
                })
            if wrinkles {
                let normal = try XCTUnwrap(result.textures.normal)
                XCTAssertEqual(normal.width, 256)
                XCTAssertEqual(normal.height, 256)
                let pixels = [UInt8](normal.pixels)
                var nonflat = 0
                for y in 0..<normal.height {
                    for x in 0..<normal.width {
                        let index = y * normal.rowStride + x * 4
                        guard pixels[index + 3] == 255 else { continue }
                        // Unmapped/transparent RG zero cannot establish a fold; only opaque valid tangent normals count.
                        let nx = Double(pixels[index]) / 255 * 2 - 1
                        let ny = Double(pixels[index + 1]) / 255 * 2 - 1
                        let nz = Double(pixels[index + 2]) / 255 * 2 - 1
                        let lengthSquared = nx * nx + ny * ny + nz * nz
                        XCTAssertGreaterThanOrEqual(nz, 0)
                        XCTAssertEqual(lengthSquared, 1, accuracy: 0.03)
                        if nz >= 0 && abs(lengthSquared - 1) <= 0.03
                            && (abs(Int(pixels[index]) - 128) > 2 || abs(Int(pixels[index + 1]) - 128) > 2)
                        {
                            nonflat += 1
                        }
                    }
                }
                XCTAssertGreaterThan(nonflat, 0)
                print(
                    "Production-pin generated cloth normal: \(nonflat) nonflat RG texels; \(result.geometry.triangleCount) triangles"
                )
            } else {
                XCTAssertNil(result.textures.normal)
            }
        }
    }
}
