import AppKit
import SwiftUI
import XCTest

@testable import Dust3DKit
@testable import Dust3DRendering

@MainActor
final class FilePreviewLayoutTests: XCTestCase {
    func testPreviewFitsNarrowSystemHostsWithoutImposingItsFloatingWindowMinimum() throws {
        let baked = try BakedMetalFixture.quad(color: BakedMetalFixture.image([255, 0, 0, 255]))
        let source = baked.geometry
        let mesh = IndexedMesh(
            vertices: source.vertices, indices: [0, 1, 2, 3, 4, 5],
            nodeCount: 1, partCount: 1,
            warning: "Untextured preview: image textures and procedural surface details are not yet displayed.")
        let document = FilePreviewDocument(
            mesh: mesh, bakedMesh: baked, materialError: nil,
            materialSourceCapabilities: .known(hasLegacySurfaceDetails: true))
        // Layout verification must not activate a test app or add a Dock item.
        NSApplication.shared.setActivationPolicy(.prohibited)
        let hosting = NSHostingController(rootView: FilePreviewView(document: document))
        for width: CGFloat in [200, 250, 640] {
            let size = hosting.sizeThatFits(in: CGSize(width: width, height: 240))
            XCTAssertLessThanOrEqual(size.width, width, "Quick Look hosts own their available width")
            XCTAssertGreaterThan(size.height, 0)
        }
    }
}
