import CryptoKit
import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

@testable import Dust3DEditor

/// Own valid 1x1 RGBA8 PNGs; expectations captured with Qt 6.12.0 QImage.scaled,
/// KeepAspectRatio and the default FastTransformation. No Qt or engine is linked here.
final class ReferenceColorQtFastScaleTests: XCTestCase {
    private struct Fixture {
        let name: String
        let png: String
        let sha256: String
        let original: [UInt8]
        let scaled: [UInt8]
    }

    func testFastScaleMatchesCapturedOpaqueTransparentAndLowAlphaSamples() throws {
        let fixtures: [Fixture] = [
            Fixture(
                name: "opaque",
                png: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMQDD75HwAD0wItuss4MAAAAABJRU5ErkJggg==",
                sha256: "d03cd797c4734ed0eeb135711c4c9368274dc829a43d115a922025f5067138e4",
                original: [17, 83, 201, 255], scaled: [17, 83, 201, 255]),
            Fixture(
                name: "zero-alpha-hidden-rgb",
                png: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMQDD7JAAAC1AEu7/9etQAAAABJRU5ErkJggg==",
                sha256: "6d1b621ceee00d479318bfc74fa0840ddda1adf4138a6da8a9aa7896c8056834", original: [17, 83, 201, 0],
                scaled: [0, 0, 0, 0]),
            Fixture(
                name: "low-alpha",
                png: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMQDD7JCAAC1QEvdWmGeQAAAABJRU5ErkJggg==",
                sha256: "ef9412cf0aeb3ddd2018b12fcec3c110ba878ed19a71b8245c86a473050a8f8d", original: [17, 83, 201, 1],
                scaled: [0, 0, 255, 1]),
        ]
        for fixture in fixtures {
            let png = try XCTUnwrap(Data(base64Encoded: fixture.png))
            XCTAssertEqual(SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined(), fixture.sha256)
            let document = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
                .applying(.setReferenceImagePNG(png))
            let unchanged = try ReferenceColorRasterCodec.prepare(
                document: document, fittedSize: ReferencePixelSize(width: 1, height: 1))
            XCTAssertEqual(Array(unchanged.raster.pixels), fixture.original, fixture.name)
            let scaled = try ReferenceColorRasterCodec.prepare(
                document: document, fittedSize: ReferencePixelSize(width: 3, height: 3))
            XCTAssertEqual(
                Array(scaled.raster.pixels), Array(repeating: fixture.scaled, count: 9).flatMap { $0 }, fixture.name)
        }
    }
}
