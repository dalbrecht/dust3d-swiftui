#if MOTE3D_EXPERIMENTAL_RIG_TEMPLATE
    import AppKit
    import SwiftUI
    import XCTest
    @testable import Dust3DEditor

    @MainActor final class RigTemplatePreviewPaletteTests: XCTestCase {
        func testAppearanceFollowsLightDarkAndIncreasedContrastPreferences() {
            XCTAssertEqual(RigTemplatePreviewPalette.appearanceName(colorScheme: .light, contrast: .standard), .aqua)
            XCTAssertEqual(RigTemplatePreviewPalette.appearanceName(colorScheme: .dark, contrast: .standard), .darkAqua)
            XCTAssertEqual(
                RigTemplatePreviewPalette.appearanceName(colorScheme: .light, contrast: .increased),
                .accessibilityHighContrastAqua)
            XCTAssertEqual(
                RigTemplatePreviewPalette.appearanceName(colorScheme: .dark, contrast: .increased),
                .accessibilityHighContrastDarkAqua)
        }
    }
#endif
