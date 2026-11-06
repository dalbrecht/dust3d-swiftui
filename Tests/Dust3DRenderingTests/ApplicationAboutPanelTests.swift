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
        XCTAssertTrue((options[.credits] as? NSAttributedString)?.string.hasPrefix(license) == true)
        XCTAssertEqual(
            options[NSApplication.AboutPanelOptionKey(rawValue: "Copyright")] as? String,
            "Copyright (c) 2018 Dust3D Project")
        XCTAssertNil(options[.applicationVersion])
        XCTAssertNil(options[.version])
    }

    func testCreditsRetainExactRootContributorAndSupporterListsOffline() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let license = try String(contentsOf: root.appendingPathComponent("LICENSE"), encoding: .utf8)
        let contributors = try String(contentsOf: root.appendingPathComponent("CONTRIBUTORS"), encoding: .utf8)
        let supporters = try String(contentsOf: root.appendingPathComponent("SUPPORTERS"), encoding: .utf8)
        let options = ApplicationAboutPanel.options(applicationName: "Dust3D Viewer")
        XCTAssertEqual(
            (options[.credits] as? NSAttributedString)?.string,
            license + "\n\nContributors\n\n" + contributors + "\n\nSupporters\n\n" + supporters)
    }

    func testMissingContributorAndSupporterResourcesRemainVisible() {
        let options = ApplicationAboutPanel.options(applicationName: "Dust3D Viewer", licenseURL: nil)
        let credits = (options[.credits] as? NSAttributedString)?.string ?? ""
        XCTAssertTrue(credits.contains("the bundled ApplicationContributors.txt file is missing"))
        XCTAssertTrue(credits.contains("the bundled ApplicationSupporters.txt file is missing"))
    }

    func testUnreadableCreditsRetainEachResourceAndReadFailureCause() throws {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let cause: String
        do {
            _ = try String(contentsOf: missing, encoding: .utf8)
            return XCTFail("The unique absent resource unexpectedly exists")
        } catch {
            cause = error.localizedDescription
        }
        let options = ApplicationAboutPanel.options(
            applicationName: "Dust3D Viewer", licenseURL: missing, contributorsURL: missing,
            supportersURL: missing)
        let credits = (options[.credits] as? NSAttributedString)?.string ?? ""
        for resource in ["ApplicationLicense.txt", "ApplicationContributors.txt", "ApplicationSupporters.txt"] {
            XCTAssertTrue(credits.contains("Unable to read \(resource): \(cause)"))
        }
    }

    func testCurrentGraphQABundleKeepsItsQADistinctionInNativeAbout() {
        let name = BuildIdentityPresentation.applicationName(
            bundleIdentifier: "org.dust3d.editor.graph-stack-qa", fallback: "Dust3D Editor")
        XCTAssertEqual(name, "Dust3D Editor QA")
        let options = ApplicationAboutPanel.options(applicationName: name)
        XCTAssertEqual(options[.applicationName] as? String, "Dust3D Editor QA")
    }

    func testMissingLicenseIsVisibleInsteadOfSilentlyDroppingAttribution() {
        let options = ApplicationAboutPanel.options(applicationName: "Dust3D Viewer", licenseURL: nil)
        let credits = (options[.credits] as? NSAttributedString)?.string ?? ""
        XCTAssertTrue(credits.contains("ApplicationLicense.txt"))
        XCTAssertTrue(credits.contains("missing"))
    }
}
