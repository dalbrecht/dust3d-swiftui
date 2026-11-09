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
        try "Embedded authors".write(
            to: try XCTUnwrap(embedded.resourceURL).appendingPathComponent("ApplicationAuthors.txt"), atomically: true,
            encoding: .utf8)
        try "Embedded contributors".write(
            to: try XCTUnwrap(embedded.resourceURL).appendingPathComponent("ApplicationContributors.txt"),
            atomically: true, encoding: .utf8)
        try "Embedded supporters".write(
            to: try XCTUnwrap(embedded.resourceURL).appendingPathComponent("ApplicationSupporters.txt"),
            atomically: true, encoding: .utf8)
        var usedDevelopment = false
        let options = ApplicationAboutPanel.options(applicationName: "Copied", applicationBundle: app) {
            usedDevelopment = true
            return app
        }
        XCTAssertEqual(
            (options[.credits] as? NSAttributedString)?.string,
            license + "\n\nAuthors\n\nEmbedded authors\n\nContributors\n\nEmbedded contributors"
                + "\n\nSupporters\n\nEmbedded supporters")
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
        XCTAssertTrue(((options[.credits] as? NSAttributedString)?.string ?? "").hasPrefix("Development license"))
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
        XCTAssertTrue((options[.credits] as? NSAttributedString)?.string.hasPrefix(license) == true)
        XCTAssertEqual(
            options[NSApplication.AboutPanelOptionKey(rawValue: "Copyright")] as? String,
            "Copyright (c) 2018 Dust3D Project")
        XCTAssertNil(options[.applicationVersion])
        XCTAssertNil(options[.version])
    }

    func testCreditsRetainExactRootAttributionListsOffline() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let license = try String(contentsOf: root.appendingPathComponent("LICENSE"), encoding: .utf8)
        let authors = try String(contentsOf: root.appendingPathComponent("AUTHORS"), encoding: .utf8)
            .replacingOccurrences(of: "\r\n", with: "\n")
        let contributors = try String(contentsOf: root.appendingPathComponent("CONTRIBUTORS"), encoding: .utf8)
        let supporters = try String(contentsOf: root.appendingPathComponent("SUPPORTERS"), encoding: .utf8)
        let options = ApplicationAboutPanel.options(applicationName: "Dust3D Viewer")
        XCTAssertEqual(
            (options[.credits] as? NSAttributedString)?.string,
            license + "\n\nAuthors\n\n" + authors + "\n\nContributors\n\n" + contributors
                + "\n\nSupporters\n\n" + supporters)
    }

    func testMissingAttributionResourcesRemainVisible() {
        let options = ApplicationAboutPanel.options(applicationName: "Dust3D Viewer", licenseURL: nil)
        let credits = (options[.credits] as? NSAttributedString)?.string ?? ""
        XCTAssertTrue(credits.contains("the bundled ApplicationAuthors.txt file is missing"))
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
            applicationName: "Dust3D Viewer", licenseURL: missing, authorsURL: missing, contributorsURL: missing,
            supportersURL: missing)
        let credits = (options[.credits] as? NSAttributedString)?.string ?? ""
        for resource in [
            "ApplicationLicense.txt", "ApplicationAuthors.txt", "ApplicationContributors.txt",
            "ApplicationSupporters.txt",
        ] {
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
