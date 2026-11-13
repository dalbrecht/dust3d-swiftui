import Foundation
import XCTest

@testable import Dust3DRendering

@MainActor final class ApplicationHelpLinkTests: XCTestCase {
    func testExplicitAcknowledgementsCommandOpensTheOfflineResource() throws {
        var opened: [URL] = []
        var errors: [ApplicationHelpLinkError] = []
        ApplicationHelpLink.upstreamAcknowledgements.open(
            using: {
                opened.append($0)
                return true
            }, report: { errors.append($0) })
        let destination = try XCTUnwrap(opened.first)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        XCTAssertEqual(opened.count, 1)
        XCTAssertTrue(destination.isFileURL)
        XCTAssertEqual(destination.lastPathComponent, "ACKNOWLEDGEMENTS.html")
        let source = try String(contentsOf: root.appendingPathComponent("ACKNOWLEDGEMENTS.html"), encoding: .utf8)
        XCTAssertEqual(
            try String(contentsOf: destination, encoding: .utf8),
            source.replacingOccurrences(of: #"[ \t]+(?=\n|$)"#, with: "", options: .regularExpression))
        XCTAssertTrue(errors.isEmpty)
    }

    func testMissingInstalledAcknowledgementsNeverOpensOrUsesDevelopmentResources() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = folder.appendingPathComponent("Copied.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info = ["CFBundleIdentifier": "test.help", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        var errors: [ApplicationHelpLinkError] = []
        ApplicationHelpLink.upstreamAcknowledgements.open(
            applicationBundle: try XCTUnwrap(Bundle(url: app)),
            developmentBundle: {
                XCTFail("An installed app must not look up build resources")
                return .main
            },
            using: { _ in
                XCTFail("An absent resource must not open")
                return true
            }, report: { errors.append($0) })
        XCTAssertEqual(errors, [.missingBundledResource("ACKNOWLEDGEMENTS.html")])
    }

    func testSupportCommandUsesTheUpstreamDestination() {
        var destinations: [URL] = []
        ApplicationHelpLink.upstreamSupport.open(
            using: {
                destinations.append($0)
                return true
            }, report: { _ in XCTFail("Valid upstream support link failed") })
        XCTAssertEqual(destinations.map(\.absoluteString), ["https://fund.dust3d.org/"])
        XCTAssertEqual(ApplicationHelpLink.upstreamSupport.title, "Support Upstream Dust3D")
    }

    func testExplicitIssueCommandOpensNativeTrackerOnce() {
        var opened: [URL] = []
        var errors: [ApplicationHelpLinkError] = []
        ApplicationHelpLink.reportIssue.open(
            using: {
                opened.append($0)
                return true
            }, report: { errors.append($0) })
        XCTAssertEqual(opened.count, 1)
        XCTAssertEqual(opened.first?.scheme, "https")
        XCTAssertEqual(opened.first?.host, "github.com")
        XCTAssertEqual(opened.first?.path, "/dalbrecht/dust3d-swiftui/issues/new")
        XCTAssertTrue(errors.isEmpty)
    }

    func testDeclinedOpenReportsItsDestinationOnce() {
        var opened: [URL] = []
        var errors: [ApplicationHelpLinkError] = []
        ApplicationHelpLink.nativeProject.open(
            using: {
                opened.append($0)
                return false
            }, report: { errors.append($0) })
        XCTAssertEqual(opened.count, 1)
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors.first, .openDeclined("https://github.com/dalbrecht/dust3d-swiftui"))
        XCTAssertTrue(errors.first?.localizedDescription.contains("macOS declined") == true)
        XCTAssertTrue(errors.first?.localizedDescription.contains(opened.first?.absoluteString ?? "missing") == true)
    }

    func testInvalidAddressesFailBeforeInvokingPlatformOpener() {
        for address in ["not a URL", "file:///tmp/help", "http://example.com"] {
            var calls = 0
            let error = ApplicationHelpLink.failure(
                address: address,
                using: { _ in
                    calls += 1
                    return true
                })
            XCTAssertEqual(error, .invalidDestination(address))
            XCTAssertEqual(calls, 0)
            XCTAssertTrue(error?.localizedDescription.contains(address) == true)
        }
    }

    func testProjectAndUpstreamRoutesRemainDistinct() {
        var project: URL?
        var upstream: URL?
        ApplicationHelpLink.nativeProject.open(
            using: {
                project = $0
                return true
            }, report: { _ in XCTFail("Valid project link failed") })
        ApplicationHelpLink.upstreamWebsite.open(
            using: {
                upstream = $0
                return true
            }, report: { _ in XCTFail("Valid upstream link failed") })
        XCTAssertEqual(project?.host, "github.com")
        XCTAssertEqual(project?.path, "/dalbrecht/dust3d-swiftui")
        XCTAssertEqual(upstream?.host, "dust3d.org")
        XCTAssertNotEqual(project, upstream)
    }
}
