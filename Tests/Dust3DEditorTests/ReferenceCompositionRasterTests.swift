import CoreGraphics
import CryptoKit
import Dust3DEditorModel
import Dust3DKit
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import Dust3DEditor

final class ReferenceCompositionRasterTests: XCTestCase {
    private func stripes() throws -> CGImage {
        let bytes: [UInt8] = [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 0, 255]
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        return try XCTUnwrap(
            CGImage(
                width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }
    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        let offset = (y * image.width + x) * 4
        return Array(UnsafeBufferPointer(start: bytes + offset, count: 4))
    }
    func testRasterCropUsesTopLeftRowsWhiteBackgroundAndPNG() throws {
        let image = try stripes()
        let size = try ReferencePixelSize(width: 2, height: 2)
        let crop = try ReferenceImageCrop(size: size, x: 0, y: 0, width: 2, height: 1)
        let source = try ReferenceCompositionSource(image: image, crop: crop)
        let result = try ReferenceCompositionRaster.compose(front: source, side: nil)
        XCTAssertEqual(result.layout.width, 2048)
        let decoded = try ReferenceImageCodec.decodePNG(result.png)
        XCTAssertEqual(decoded.width, 2048)
        XCTAssertEqual(decoded.height, 512)
        XCTAssertEqual(try pixel(decoded, x: 128, y: 256), [255, 0, 0, 255])
        XCTAssertEqual(try pixel(decoded, x: 896, y: 256), [0, 255, 0, 255])
        XCTAssertEqual(try pixel(decoded, x: 1536, y: 256), [255, 255, 255, 255])
    }
    func testFixedPointCompositionMatchesQtSmoothResampling() throws {
        let fixtures = [
            (1, 400, false, "8aa4f899a1ae08a0c4a69dfdc7602d9e9c4da07d3d014e3bdbfacdb69f9249a6"),
            (1, 700, false, "f2fb3cf9c238a415b7ef0746abc942a3339427e9f506d2783303dee9eed5aabd"),
            (19, 512, true, "ada671f3f7bd9b320c304b41a4238db78e0cc0850fb06fa6dafb2c3fadf6508b"),
            (7, 9, false, "dfa3aa5112e22b45b802a1b7571b909d932a8d11e897e84793b1b963a53ab285"),
            (7, 9, true, "6d108d3c2742214c8e41536ff5c7aa4e67ed9fb9945c9b2924ab9668b47b777f"),
            (7, 12, true, "85f66cabc2c7767aefa64b83427fbb7a70dc1628e848462f97f2550270839023"),
            (701, 893, false, "8e60941b7a02883089cf39cb089103459ee72e44df8c15137685e4e3c676d2e8"),
            (453, 1201, false, "ba151442bb927afcf199e46f2ac946ee7746617d242877dddd9341d0a5587af6"),
            (453, 1201, true, "a3dc2fbddbbee758acac0856d32750d694c336da9bc7ece0edff7daf764cfdce"),
        ]
        for (width, height, hasAlpha, expected) in fixtures {
            var bytes = Data(capacity: width * height * 4)
            for y in 0..<height {
                for x in 0..<width {
                    bytes.append(UInt8((x * 71 + y * 13) % 256))
                    bytes.append(UInt8((x * 23 + y * 29) % 256))
                    bytes.append(UInt8((x * 97 + y * 7) % 256))
                    bytes.append(hasAlpha ? UInt8((x * 19 + y * 83) % 256) : 255)
                }
            }
            var preview = bytes
            if hasAlpha {
                for offset in stride(from: 0, to: preview.count, by: 4) {
                    for channel in 0..<3 {
                        preview[offset + channel] = UInt8(
                            (Int(bytes[offset + channel]) * Int(bytes[offset + 3]) + 127) / 255)
                    }
                }
            }
            let provider = try XCTUnwrap(CGDataProvider(data: preview as CFData))
            let image = try XCTUnwrap(
                CGImage(
                    width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                    bytesPerRow: width * 4, space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                    bitmapInfo: CGBitmapInfo(
                        rawValue: (hasAlpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue),
                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
            let source = try ReferenceCompositionSource(
                image: image, crop: .init(size: .init(width: width, height: height)),
                straightRGBA: hasAlpha ? bytes : nil)
            let result = try ReferenceCompositionRaster.compose(front: source, side: nil)
            let rgba = try XCTUnwrap(result.image.dataProvider?.data) as Data
            let digest = SHA256.hash(data: rgba).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(digest, expected, "\(width) × \(height)")
        }
    }

    func testServiceImportsNormalizedPixelsAndComposesOnItsActor() async throws {
        let image = try stripes()
        let png = try ReferenceImageCodec.encodePNG(image)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("composition-\(UUID().uuidString).png")
        try png.write(to: url)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        let service = ReferenceCompositionService()
        let imported = try await service.importSource(url: url)
        XCTAssertEqual(imported.crop, .init(size: try .init(width: 2, height: 2)))
        XCTAssertFalse(imported.isMirrored)
        let result = try await service.compose(front: imported, side: imported)
        XCTAssertEqual(result.layout.width, 1024)
        XCTAssertEqual(try ReferenceImageCodec.decodePNG(result.png).height, 512)
    }

    func testCompositionImportRetainsStraightPNGChannels() async throws {
        let png = try XCTUnwrap(
            Data(
                base64Encoded:
                    "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAGklEQVR4nGNYYnWOnZmFlYFBwaGB5ZcS638AJsMExMfuGgkAAAAASUVORK5CYII="
            ))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "straight-reference-\(UUID().uuidString).png")
        try png.write(to: url)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        let source = try await ReferenceCompositionService().importSource(url: url)
        XCTAssertEqual(
            source.straightRGBA,
            Data([
                164, 58, 206, 7, 3, 4, 5, 0, 32, 64, 128, 4, 250, 34, 5, 255,
            ]))
    }

    func testRGBTransparencyKeyRetainsStraightPNGChannels() async throws {
        let png = try XCTUnwrap(
            Data(
                base64Encoded:
                    "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAABnRSTlMAHgBQAKrryUo0AAAAFUlEQVR4nGOQC1i1xOocg4JDA5AFACEoBL306nrqAAAAAElFTkSuQmCC"
            ))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "keyed-reference-\(UUID().uuidString).png")
        try png.write(to: url)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        let source = try await ReferenceCompositionService().importSource(url: url)
        XCTAssertEqual(
            source.straightRGBA,
            Data([
                30, 80, 170, 0, 164, 58, 206, 255, 32, 64, 128, 255, 30, 80, 170, 0,
            ]))
    }

    func testIndexedPNGImportRetainsPaletteAlphaAndMatchesQt() async throws {
        let fixtures = [
            (
                "iVBORw0KGgoAAAANSUhEUgAAAAcAAAAJCAMAAADJhsaRAAAADFBMVEUeUKrICWRheA0VyZvqxXS5AAAABHRSTlMAQJ//GNKSAgAAABtJREFUeJxjYGBkYgZiBmYIg4EJwoAKwxmE5AENOABevHNQlAAAAABJRU5ErkJggg==",
                "d3aeb0d3f14253efc53f2591ecb1b0d38f9115e74b160769e77f36a38ad5ad86"
            ),
            (
                "iVBORw0KGgoAAAANSUhEUgAAAAcAAAAICAMAAAAC2hU0AAAADFBMVEUeUKrICWRheA0VyZvqxXS5AAAABHRSTlMAQJ//GNKSAgAAABtJREFUeJxjYGBkYgZiBmYIg4EJwoAKwxm45AEKcABVpzyi+wAAAABJRU5ErkJggg==",
                "e90453e142703f783d4794207b9bbc5f6e781c51b8172872cbbb7f5c1aa16193"
            ),
            (
                "iVBORw0KGgoAAAANSUhEUgAAAAcAAAAMCAMAAACZS1ciAAAADFBMVEUeUKrICWRheA0VyZvqxXS5AAAABHRSTlMAQJ//GNKSAgAAABxJREFUeJxjYGBkYgZiBmYIg4EJwoAKwxnkygMAF4gAfywYpWcAAAAASUVORK5CYII=",
                "097b704a237ba25e5700c8fbe8a0196b459fb1c67200b168408f5b72cd19b959"
            ),
        ]
        let service = ReferenceCompositionService()
        for (encoded, expected) in fixtures {
            let png = try XCTUnwrap(Data(base64Encoded: encoded))
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                "indexed-reference-\(UUID().uuidString).png")
            try png.write(to: url)
            addTeardownBlock { try FileManager.default.removeItem(at: url) }
            let source = try await service.importSource(url: url)
            XCTAssertTrue(source.isIndexed)
            XCTAssertEqual(
                try XCTUnwrap(source.straightRGBA).prefix(16),
                Data([
                    30, 80, 170, 0, 200, 9, 100, 64, 97, 120, 13, 159, 21, 201, 155, 255,
                ]))
            let result = try await service.compose(front: source, side: nil)
            let pixels = try XCTUnwrap(result.image.dataProvider?.data) as Data
            let digest = SHA256.hash(data: pixels).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(digest, expected)
        }
    }

    func testGrayscalePNGImportRetainsAlphaAndTransparencyKeys() async throws {
        func importPNG(_ encoded: String) async throws -> ReferenceCompositionSource {
            let png = try XCTUnwrap(Data(base64Encoded: encoded))
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                "gray-reference-\(UUID().uuidString).png")
            try png.write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            return try await ReferenceCompositionService().importSource(url: url)
        }

        let eightBit = try await importPNG(
            "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAQAAABeK7cBAAAADUlEQVR4nGOQd1h7GwADdgHoozSGvwAAAABJRU5ErkJggg==")
        XCTAssertEqual(eightBit.straightRGBA, Data([31, 31, 31, 64, 173, 173, 173, 219]))
        XCTAssertNil(eightBit.wideImage)

        let sixteenBit = try await importPNG(
            "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABEAQAAAAOu2tCAAAAEUlEQVR4nGOQV3DgWLvudj0ACnwDPa8LgL0AAAAASUVORK5CYII=")
        let wide = try XCTUnwrap(sixteenBit.wideImage)
        XCTAssertEqual(wide.bitsPerComponent, 16)
        XCTAssertEqual(wide.bitsPerPixel, 32)
        XCTAssertEqual(wide.width, 2)
        XCTAssertEqual(wide.height, 1)
        XCTAssertNil(sixteenBit.straightRGBA)

        let indexed = try await importPNG(
            "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABAgAAAACb+Tj3AAAAAnRSTlMAA++anIIAAAAKSURBVHicY7gAAADSANHb2Q63AAAAAElFTkSuQmCC"
        )
        let indexedPixels = try XCTUnwrap(indexed.straightRGBA)
        XCTAssertTrue(indexed.isIndexed)
        XCTAssertEqual(indexedPixels[3], 0)
        XCTAssertEqual(indexedPixels.suffix(4), Data([85, 85, 85, 255]))

        let keyedWide = try await importPNG(
            "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABEAAAAACB2fwVAAAAAnRSTlMAH/ubwM0AAAANSURBVHicY2CQX7sOAAJqAXu8ahwxAAAAAElFTkSuQmCC"
        )
        XCTAssertEqual(keyedWide.wideImage?.bitsPerPixel, 32)
        XCTAssertNil(keyedWide.straightRGBA)
    }

    func testDirectReferenceImportStoresDecodableWideGrayscaleAlpha() async throws {
        let encoded =
            "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABEAQAAAAOu2tCAAAAEUlEQVR4nGOQV3DgWLvudj0ACnwDPa8LgL0AAAAASUVORK5CYII="
        let source = try XCTUnwrap(Data(base64Encoded: encoded))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "wide-gray-direct-reference-\(UUID().uuidString).png")
        try source.write(to: url)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }

        let stored = try await ReferenceImageService().importImage(url: url)
        let reopened = try ReferenceImageCodec.decodePNG(stored)
        XCTAssertEqual(reopened.width, 2)
        XCTAssertEqual(reopened.height, 1)
        XCTAssertEqual(reopened.bitsPerComponent, 16)
        let raw = try XCTUnwrap(ReferenceImageCodec.straightStandardPNGImage(stored))
        let samples = try ImageSampleLayout(raw)
        let storage = try XCTUnwrap(raw.dataProvider?.data)
        let pixels = try XCTUnwrap(CFDataGetBytePtr(storage))
        XCTAssertEqual(try samples.rgba16(pixels).3, 16392)
        XCTAssertEqual(try samples.rgba16(pixels.advanced(by: samples.bytesPerPixel)).3, 56191)
    }

    func testWidePNGImportRetainsOriginalChannelPrecision() async throws {
        let png = try XCTUnwrap(
            Data(
                base64Encoded:
                    "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABEAYAAACksqPJAAAAGUlEQVR4nGNgZGSprmUUZI7KYL5/WvHfbQAdzgV9aeiJnQAAAABJRU5ErkJggg=="
            ))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "wide-reference-\(UUID().uuidString).png")
        try png.write(to: url)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        let source = try await ReferenceCompositionService().importSource(url: url)
        let wide = try XCTUnwrap(source.wideImage)
        XCTAssertEqual(wide.bitsPerComponent, 16)
        XCTAssertEqual(wide.width, 2)
        XCTAssertEqual(wide.height, 1)
        XCTAssertNil(source.straightRGBA)
    }

    func testWideRGBPNGPreservesOpaqueAndKeyedSamples() async throws {
        // Qt reads the keyed fixture as an equivalent RGBA PNG with explicit alpha.
        let fixtures = [
            (
                "iVBORw0KGgoAAAANSUhEUgAAAAcAAAAJEAIAAAAhqn23AAABjklEQVR4nAGDAXz+AAAAAAAAAEdHFzNhRY6OLmbCitXVRZkjzx0cXMyFFGRjc//mWauqizJHngANKx0dBwlUcjRQaE6buUuDyZPjAGK2KtgqR3npjB1xjpEc7WK41ahPTqcAGlY6Og4SYZ1RbW9XqORooNCc8Ct/0zHhN3KXBpMmfrmuOfRrxgDFbFWwACeBV1cVG27Ibop2YLYPhb3Xpf1WnPA46kSdtCOaL4vky1b7dNMr4olcuQA0rHR0HCR784unfWnDOqLa3q4KgboNP/NRyNFAoTiZD+hzAn3gVv+mY8IAQdeRkSMtiR6oxIRy0GW/9+W3F6zXKkb8XvPuXahBpjoFkAmG7YEcw2rLAE8Crq4qNpZJxeGLe92Q3RTswCTX9EdOBWweC3qvSrNlIq0Qj/qsOeBx1ABcLcvLMT+jdOL+koTqu/ox88kyAhFkVQ55SSiXtlPAkD/KF5gH11b9eN0AaVjo6DhIsJ8AG5mN9+YXTvrSPy0ugVwXhnRFtL1czbtc5x6hFQJ0Gn/m6Um1gQuFK60AAAAASUVORK5CYII=",
                48, "4c82ef37c4e8915c052b980ceb67a104a08a434ba8550ee7015696f6c773091a"
            ),
            (
                "iVBORw0KGgoAAAANSUhEUgAAAAcAAAAJEAIAAAAhqn23AAAABnRSTlMBLB9AQmhYDRjVAAABQ0lEQVR4nGNg1JF3cMpwdxc3TnTt69NLO9QFEZGViTnTKpKSXPz/WSREhIFXW1aWnTOkyCQgww8i9JghaZvWDS33ypc9shCRHVdX+PstZ5AKs7LiE4IIrXiSseDCnA/a9ZcNH0JE6naus/ySfYzhaE7oBgaIUN6JvK6yhG38rXuvL4WIuMzdojxLv/vJ6bDfJVAHmKwpKZFRqf7cvbw2EyLE1biL1/5z4ImLDgstICIPwv4vSz7E4Hh94kRlXYjQhdT9359uF19zXcvtD0RkmRXrBM62t40yh7NOQx0wzfPow+7quxPuirw5ABHJkeOuWu+1OVVprUA/1AExuqdPG9ovLnn0b1ILRMiISTAllK/SU2P6tmCICPv1sL8VdxkyI168sPCACH1/Ju7365K9rl5jjDhE5OzumOdyC0WZSqTqnwEAp76RoDVwTjQAAAAASUVORK5CYII=",
                64, "9b277077e107cad2b7b03a1e808b552793f338065814ff5629f9481a19530cc5"
            ),
        ]
        let service = ReferenceCompositionService()
        for (encoded, bitsPerPixel, expected) in fixtures {
            let png = try XCTUnwrap(Data(base64Encoded: encoded))
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                "wide-rgb-reference-\(UUID().uuidString).png")
            try png.write(to: url)
            addTeardownBlock { try FileManager.default.removeItem(at: url) }
            let source = try await service.importSource(url: url)
            XCTAssertEqual(source.wideImage?.bitsPerPixel, bitsPerPixel)
            let result = try await service.compose(front: source, side: nil)
            let pixels = try XCTUnwrap(result.image.dataProvider?.data) as Data
            let digest = SHA256.hash(data: pixels).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(digest, expected)
        }
    }

    func testPackedBMPReferenceUsesQtChannelExpansion() async throws {
        let bmp = try XCTUnwrap(
            Data(
                base64Encoded:
                    "Qk3SAAAAAAAAAEIAAAAoAAAABwAAAAkAAAABABAAAwAAAJAAAAAAAAAAAAAAAAAAAAAAAAAAAPgAAOAHAAAfAAAAR2/zr7/wazk3gsPKjxMAAEZeEqfe74owNnHiua4CAABlTTGW/d6JJ1VoAbHO+QAAhERQjfzNqBZ0XyGgzegAAKMzT3wbxccNlFYgl+zfAACiIm5rOrTn/JNFX44L1wAAwRmNYlqr5uuyNH59KsYAAOAIrVFZmgXj0SuddCm1AAAAAKxAeIkk0vAanGNIrAAA"
            ))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "packed-reference-\(UUID().uuidString).bmp")
        try bmp.write(to: url)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        let service = ReferenceCompositionService()
        let source = try await service.importSource(url: url)
        let result = try await service.compose(front: source, side: nil)
        let pixels = try XCTUnwrap(result.image.dataProvider?.data) as Data
        let digest = SHA256.hash(data: pixels).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, "cee5823f8012b2eda924cbe0dbcf0770b5b86a4365ada346bac88c604577b7f4")
    }

    func testTransparentGIFReferenceMatchesQtCanvas() async throws {
        let gif = try XCTUnwrap(
            Data(
                base64Encoded:
                    "R0lGODdhBwAJAOYAAAAAAKQECGsIrTEQVfYV+kMbXgwcBvAeabAfEHgntT0tXI0vw1U1afc4cBo6Dr4+FtdDJIREvJxMyGBRcAZVdidXFhtbg8tbHeJiKhpmgKho0GpqgGNz5DJ1Gyp4jO9/MbWE1qqLRXuMfkKQI3CR7DaWkmaZ//qeOMOh3benTIiohE6uKkOxmAq4P7+/Vc/A5VzLMIvL+ZnMmVHQnxbWRt/f6tLgW6LikZfnAWjoN13tpyTzTer4893+Yq7/mv///wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACH5BAkAAEAALAAAAAAHAAkAAAc7gECCQBYcIQYMEhgeJCkOExofJYIVgywxNh0iKC0zOD0jKi80OgFAK4NACA0wNzwDCQ8UOT4EChEXQIEAOw=="
            ))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "reference-transparent-\(UUID().uuidString).gif")
        try gif.write(to: url)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }

        let service = ReferenceCompositionService()
        let source = try await service.importSource(url: url)
        let result = try await service.compose(front: source, side: nil)
        let pixels = try XCTUnwrap(result.image.dataProvider?.data) as Data
        let digest = SHA256.hash(data: pixels).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, "bde1a1f845a1d6c7d1b40cb32a2710e4921820044c830e623fbf62acb0045d18")
    }

    func testWidePNGSamplingMatchesQt() throws {
        let fixtures = [
            (453, 1201, "5b4c3f964295b3fd1df47077e7f099867c83e2b7ac87c7d59d049fc2ba1f6605"),
            (7, 12, "280bd48ef8003d36fd4a3be826462c9a4217e1b724f440a32f5257e107e349f4"),
        ]
        for (width, height, expected) in fixtures {
            var pixels = Data(capacity: width * height * 8)
            for y in 0..<height {
                for x in 0..<width {
                    for channel in [
                        x * 18247 + y * 3371, x * 5939 + y * 7453,
                        x * 24901 + y * 1801, x * 4903 + y * 21373,
                    ] {
                        pixels.append(UInt8(truncatingIfNeeded: channel >> 8))
                        pixels.append(UInt8(truncatingIfNeeded: channel))
                    }
                }
            }
            let provider = try XCTUnwrap(CGDataProvider(data: pixels as CFData))
            let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
            let wide = try XCTUnwrap(
                CGImage(
                    width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 64, bytesPerRow: width * 8,
                    space: colorSpace,
                    bitmapInfo: [.byteOrder16Big, CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)],
                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
            let source = try ReferenceCompositionSource(
                image: wide, crop: .init(size: .init(width: width, height: height)), wideImage: wide)
            let result = try ReferenceCompositionRaster.compose(front: source, side: nil)
            let output = try XCTUnwrap(result.image.dataProvider?.data) as Data
            let digest = SHA256.hash(data: output).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(digest, expected, "\(width) × \(height)")
        }
    }

    func testTaggedWideGamutImportKeepsColorManagedRendering() async throws {
        let source = try await importTaggedPNG(colorSpace: CGColorSpace.displayP3, orientation: 1)
        XCTAssertEqual(source.image.width, 2)
        XCTAssertEqual(source.image.height, 1)
        XCTAssertNil(source.straightRGBA)
    }

    func testOrientationTaggedImportKeepsNormalizedCoordinates() async throws {
        let source = try await importTaggedPNG(colorSpace: CGColorSpace.sRGB, orientation: 6)
        XCTAssertEqual(source.image.width, 1)
        XCTAssertEqual(source.image.height, 2)
        XCTAssertNil(source.straightRGBA)
    }

    private func importTaggedPNG(colorSpace: CFString, orientation: Int) async throws -> ReferenceCompositionSource {
        let space = try XCTUnwrap(CGColorSpace(name: colorSpace))
        let provider = try XCTUnwrap(CGDataProvider(data: Data([96, 10, 20, 128, 21, 80, 35, 128]) as CFData))
        let image = try XCTUnwrap(
            CGImage(
                width: 2, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
                space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let output = NSMutableData()
        let writer = try XCTUnwrap(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "tagged-reference-\(UUID().uuidString).png")
        try (output as Data).write(to: url)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return try await ReferenceCompositionService().importSource(url: url)
    }

    func testSideMirrorAndSourceSizeMismatch() throws {
        let image = try stripes()
        let crop = ReferenceImageCrop(size: try ReferencePixelSize(width: 2, height: 2))
        let source = try ReferenceCompositionSource(image: image, crop: crop, isMirrored: true)
        let result = try ReferenceCompositionRaster.compose(front: nil, side: source)
        let decoded = try ReferenceImageCodec.decodePNG(result.png)
        XCTAssertEqual(try pixel(decoded, x: 128, y: 128), [255, 255, 255, 255])
        XCTAssertEqual(try pixel(decoded, x: 576, y: 64), [0, 255, 0, 255])
        XCTAssertEqual(try pixel(decoded, x: 960, y: 448), [0, 0, 255, 255])
        let wrong = ReferenceImageCrop(size: try ReferencePixelSize(width: 1, height: 1))
        XCTAssertThrowsError(try ReferenceCompositionSource(image: image, crop: wrong))
        XCTAssertThrowsError(try ReferenceCompositionRaster.compose(front: nil, side: nil))
    }
}
