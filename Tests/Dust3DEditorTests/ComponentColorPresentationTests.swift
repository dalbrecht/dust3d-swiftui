import AppKit
import Dust3DDocument
import SwiftUI
import XCTest

@testable import Dust3DEditor

@MainActor
final class ComponentColorPresentationTests: XCTestCase {
    func testColorPickerConversionRoundTripsEightBitChannelsAndAlpha() throws {
        for value in [
            DocumentColor(red: 0, green: 255, blue: 128), DocumentColor(red: 1, green: 2, blue: 3, alpha: 4),
            DocumentColor(red: 255, green: 0, blue: 0, alpha: 0),
        ] {
            XCTAssertEqual(DocumentColorPresentation.value(from: DocumentColorPresentation.color(value)), value)
        }
    }

    func testUnconvertiblePatternColorDoesNotInventColorChannels() {
        let pattern = NSColor(patternImage: NSImage(size: NSSize(width: 1, height: 1)))
        XCTAssertNil(DocumentColorPresentation.value(from: Color(nsColor: pattern)))
    }

    func testChannelConversionRoundsOnlyFiniteBoundedValues() {
        XCTAssertEqual(DocumentColorPresentation.channel(0), 0)
        XCTAssertEqual(DocumentColorPresentation.channel(1), 255)
        XCTAssertEqual(DocumentColorPresentation.channel(0.5), 128)
        for invalid in [-0.001, 1.001, .infinity, -.infinity, .nan] {
            XCTAssertNil(DocumentColorPresentation.channel(invalid))
        }
    }
}
