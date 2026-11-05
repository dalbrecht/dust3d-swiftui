import AppKit
import CryptoKit
import Dust3DDocument
import Dust3DEditorModel
import Dust3DKit
import SwiftUI
import XCTest

@testable import Dust3DEditor

/// Review artifacts only: no product display policy or golden snapshot is installed by these tests.
final class ReferenceColorDisplayComparisonTests: XCTestCase {
    @MainActor func testCurrentAndProposedReferenceInterpolationRenderUsingSameLogicalFrame() throws {
        let checker = Data(
            (0..<16).flatMap { index -> [UInt8] in
                let value: UInt8 = ((index / 4 + index % 4) % 2 == 0) ? 255 : 0
                return [value, value, value, 255]
            })
        let p3 = Data([100, 80, 60, 255, 200, 150, 100, 128, 20, 170, 80, 255, 255, 20, 60, 255])
        let fixtures: [(String, Data)] = [
            ("checker", try encode(checker, width: 4, height: 4, space: CGColorSpaceCreateDeviceRGB())),
            (
                "gray",
                try XCTUnwrap(
                    Data(
                        base64Encoded:
                            "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAAAAADRSSBWAAAAC0lEQVR4nGMQPAEAAO0A2ompDWMAAAAASUVORK5CYII="
                    ))
            ),
            (
                "palette",
                try XCTUnwrap(
                    Data(
                        base64Encoded:
                            "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABAQMAAADO7O3JAAAABlBMVEX/AAAAAP9sof2OAAAAAnRSTlOAAToXZeUAAAAKSURBVHicY3AAAABCAEEpN/TvAAAAAElFTkSuQmCC"
                    ))
            ),
            ("p3", try encode(p3, width: 2, height: 2, space: XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3)))),
            ("custom-gray", try ReferenceColorPNGFixtures.customGrayPNG()),
        ]
        var manifest: [[String: Any]] = []
        for (name, png) in fixtures {
            let document = try Dust3DDocument(data: Dust3DDocument.emptyArchive()).applying(.setReferenceImagePNG(png))
            let original = try ReferenceImageCodec.decodePNG(png)
            let aspect = Double(original.width) / Double(original.height)
            let canvasWidth = aspect * 160 + 72
            let projection = CanvasProjection(
                bounds: .init(nodes: [], referenceImageAspectRatio: aspect), plane: .front,
                width: canvasWidth, height: 232)
            let center = projection.point(for: .init(x: aspect / 2, y: 0.5, z: aspect / 2))
            let frameWidth = aspect * projection.scale
            let frameHeight = projection.scale
            let fittedSize = try ReferencePixelSize(
                width: Int(frameWidth.rounded()), height: Int(frameHeight.rounded()))
            let result = try ReferenceColorRasterCodec.prepare(document: document, fittedSize: fittedSize)
            let pixels = try bytes(result.raster)
            let proposed = result.displayImage
            let policy =
                proposed.bitsPerPixel == 16
                ? "original monochrome profile + fitted GA8 pixels" : "original RGB/base profile + fitted RGBA8 pixels"
            XCTAssertEqual(proposed.colorSpace?.numberOfComponents, proposed.bitsPerPixel == 16 ? 1 : 3)
            let sourceDecoded = try MeshPNGDecoder.decode(png, imageID: "diagnostic")
            let nativePixels = try XCTUnwrap(original.dataProvider?.data) as Data
            for scheme in [ColorScheme.light, .dark] {
                let comparison = VStack(alignment: .leading, spacing: 12) {
                    Text("Reference interpolation review · \(name)").font(.headline)
                    Text(
                        "Same logical canvas, reference frame and opacity 0.5. Proposed fitted grid is explicit 1× logical points."
                    )
                    .font(.caption)
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading) {
                            Text("Current SwiftUI default").font(.caption)
                            ZStack {
                                Image(decorative: original, scale: 1).resizable()
                                    .frame(width: frameWidth, height: frameHeight)
                                    .position(x: center.x, y: center.y).opacity(0.5)
                            }.frame(width: canvasWidth, height: 232)
                        }
                        VStack(alignment: .leading) {
                            Text("Nearest fitted pixels").font(.caption)
                            ZStack {
                                Image(decorative: proposed, scale: 1).interpolation(.none).resizable()
                                    .frame(width: frameWidth, height: frameHeight)
                                    .position(x: center.x, y: center.y).opacity(0.5)
                            }.frame(width: canvasWidth, height: 232)
                        }
                    }
                    Text(
                        "Display profile: \(policy). No RGB fallback or color conversion is applied."
                    )
                    .font(.caption)
                }
                let rendered = try InspectorRenderer.png(comparison, width: canvasWidth * 2 + 48, scheme: scheme)
                let bitmap = try XCTUnwrap(NSBitmapImageRep(data: rendered))
                XCTAssertGreaterThan(bitmap.pixelsWide, 0)
                XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
                let filename = "reference-interpolation-\(name)-\(scheme == .dark ? "dark" : "light").png"
                if let output = ProcessInfo.processInfo.environment["DUST3D_UI_QA_OUTPUT_DIR"] {
                    let directory = URL(fileURLWithPath: output, isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try rendered.write(to: directory.appendingPathComponent(filename), options: .atomic)
                }
                manifest.append([
                    "file": filename, "fixture": name, "sourcePNG_SHA256": sha(png),
                    "sourceDecodedStraightRGBA_SHA256": sha(sourceDecoded.pixels),
                    "nativeReferenceProvider_SHA256": sha(nativePixels), "fittedStraightRGBA_SHA256": sha(pixels),
                    "sourceProfileKind": String(describing: result.sourceColorSpace?.model),
                    "proposedDisplayProfilePolicy": policy,
                    "fittedDisplayProvider_SHA256": sha(try providerBytes(proposed)),
                    "fittedDisplayBitsPerPixel": proposed.bitsPerPixel,
                    "canvasLogicalWidth": canvasWidth, "canvasLogicalHeight": 232,
                    "referenceLogicalWidth": frameWidth, "referenceLogicalHeight": frameHeight,
                    "referenceLogicalOriginX": center.x - frameWidth / 2,
                    "referenceLogicalOriginY": center.y - frameHeight / 2,
                    "fittedWidth": fittedSize.width, "fittedHeight": fittedSize.height, "opacity": 0.5,
                    "renderedPixelWidth": bitmap.pixelsWide, "renderedPixelHeight": bitmap.pixelsHigh,
                    "implicitBackingScaleUsedForFittedRaster": false, "productUIChanged": false,
                ])
            }
        }
        if let output = ProcessInfo.processInfo.environment["DUST3D_UI_QA_OUTPUT_DIR"] {
            let url = URL(fileURLWithPath: output, isDirectory: true).appendingPathComponent(
                "reference-interpolation-manifest.json")
            try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(
                to: url, options: .atomic)
        }
    }

    private func providerBytes(_ image: CGImage) throws -> Data { try XCTUnwrap(image.dataProvider?.data) as Data }

    private func cgImage(_ bytes: Data, width: Int, height: Int, space: CGColorSpace) throws -> CGImage {
        let provider = try XCTUnwrap(CGDataProvider(data: bytes as CFData))
        return try XCTUnwrap(
            CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: space, bitmapInfo: .init(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    private func encode(_ bytes: Data, width: Int, height: Int, space: CGColorSpace) throws -> Data {
        try ReferenceImageCodec.encodePNG(cgImage(bytes, width: width, height: height, space: space))
    }

    private func bytes(_ raster: ReferenceColorRaster) throws -> Data {
        var result = Data()
        for y in 0..<raster.size.height {
            for x in 0..<raster.size.width {
                let color = try XCTUnwrap(raster.color(x: x, y: y))
                result.append(contentsOf: [color.red, color.green, color.blue, color.alpha])
            }
        }
        return result
    }

    private func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
