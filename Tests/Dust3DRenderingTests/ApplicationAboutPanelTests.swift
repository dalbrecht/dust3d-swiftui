import AppKit
import XCTest

@testable import Dust3DRendering

@MainActor
final class ApplicationAboutPanelTests: XCTestCase {
    func testPackagedAboutUsesEmbeddedResourcesWithoutDevelopmentLookup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try resourceFixture(at: root.appendingPathComponent("Copied.app"), identifier: "test.app")
        let resources = try XCTUnwrap(app.resourceURL)
        let embedded = try resourceFixture(
            at: resources.appendingPathComponent("Dust3DNative_Dust3DRendering.bundle"), identifier: "test.resources")
        let license = "Copyright Embedded Owner\nEmbedded license only"
        try license.write(
            to: try XCTUnwrap(embedded.resourceURL).appendingPathComponent("ApplicationLicense.txt"), atomically: true,
            encoding: .utf8)
        var usedDevelopment = false
        let options = ApplicationAboutPanel.options(applicationName: "Copied", applicationBundle: app) {
            usedDevelopment = true
            return app
        }
        XCTAssertEqual((options[.credits] as? NSAttributedString)?.string, license)
        XCTAssertFalse(usedDevelopment)
    }

    func testMissingPackagedResourcesNeverConsultPotentiallyUnavailableBuildBundle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try resourceFixture(at: root.appendingPathComponent("Copied.app"), identifier: "test.missing")
        var usedDevelopment = false
        let options = ApplicationAboutPanel.options(applicationName: "Copied", applicationBundle: app) {
            usedDevelopment = true
            return app
        }
        XCTAssertFalse(usedDevelopment)
        XCTAssertTrue(((options[.credits] as? NSAttributedString)?.string ?? "").contains("missing"))
    }

    func testCommandLineAboutCanUseDevelopmentResources() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let command = try resourceFixture(at: root.appendingPathComponent("Command.bundle"), identifier: "test.command")
        let development = try resourceFixture(
            at: root.appendingPathComponent("Development.bundle"), identifier: "test.development")
        try "Development license".write(
            to: try XCTUnwrap(development.resourceURL).appendingPathComponent("ApplicationLicense.txt"),
            atomically: true, encoding: .utf8)
        var usedDevelopment = false
        let options = ApplicationAboutPanel.options(applicationName: "Command", applicationBundle: command) {
            usedDevelopment = true
            return development
        }
        XCTAssertTrue(usedDevelopment)
        XCTAssertEqual((options[.credits] as? NSAttributedString)?.string, "Development license")
    }

    private func resourceFixture(at url: URL, identifier: String) throws -> Bundle {
        try FileManager.default.createDirectory(
            at: url.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": identifier, "CFBundlePackageType": url.pathExtension == "app" ? "APPL" : "BNDL",
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(
            to: url.appendingPathComponent("Contents/Info.plist"))
        return try XCTUnwrap(Bundle(url: url))
    }

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
