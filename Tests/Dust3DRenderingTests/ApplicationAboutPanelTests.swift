import AppKit
import XCTest

@testable import Dust3DRendering

@MainActor
final class ApplicationAboutPanelTests: XCTestCase {
    func testAboutUsesExactBundledLicenseAndQANameWhileLeavingVersionDefaultsToAppKit() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let license = try String(contentsOf: root.appendingPathComponent("LICENSE"), encoding: .utf8)
        let options = ApplicationAboutPanel.options(applicationName: "Dust3D Editor QA")
        XCTAssertEqual(options[.applicationName] as? String, "Dust3D Editor QA")
        XCTAssertEqual((options[.credits] as? NSAttributedString)?.string, license)
        XCTAssertEqual(
            options[NSApplication.AboutPanelOptionKey(rawValue: "Copyright")] as? String,
            "Copyright (c) 2018 Dust3D Project")
        XCTAssertNil(options[.applicationVersion])
        XCTAssertNil(options[.version])
    }

    func testMissingLicenseIsVisibleInsteadOfSilentlyDroppingAttribution() {
        let options = ApplicationAboutPanel.options(applicationName: "Dust3D Viewer", licenseURL: nil)
        let credits = (options[.credits] as? NSAttributedString)?.string ?? ""
        XCTAssertTrue(credits.contains("ApplicationLicense.txt"))
        XCTAssertTrue(credits.contains("missing"))
    }
}
