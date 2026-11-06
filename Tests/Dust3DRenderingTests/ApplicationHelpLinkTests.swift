import Foundation
import XCTest

@testable import Dust3DRendering

@MainActor final class ApplicationHelpLinkTests: XCTestCase {
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
