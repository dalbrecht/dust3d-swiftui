import Foundation
import XCTest

@testable import Dust3DEditor

@MainActor
final class EditorLaunchNeutralPreviewTests: XCTestCase {
    func testParsesColorOptionInOrderAndTreatsNamesAfterDelimiterAsPaths() throws {
        let url = URL(fileURLWithPath: "/tmp/a.ds3")
        for truthy in ["true", "True", "1"] {
            XCTAssertEqual(
                try EditorLaunchRequest(arguments: ["Editor", "-toggle-color", truthy, url.path]),
                .open([url], hidesPreviewColors: true))
        }
        XCTAssertEqual(
            try EditorLaunchRequest(arguments: ["Editor", "-toggle-color", "true", "-toggle-color", "0", url.path]),
            .open([url]))
        XCTAssertEqual(
            try EditorLaunchRequest(arguments: ["Editor", "-toggle-color", "true"]),
            .none)
        XCTAssertEqual(
            try EditorLaunchRequest(arguments: ["Editor", "--", "-toggle-color.ds3"]),
            .open([URL(fileURLWithPath: "-toggle-color.ds3").standardizedFileURL]))
        XCTAssertThrowsError(try EditorLaunchRequest(arguments: ["Editor", url.path, "-toggle-color"])) {
            XCTAssertEqual($0 as? EditorLaunchError, .invalidColorArgument)
        }
    }

    func testOnlyNewExactDocumentCanClaimOnceAcrossMultipleOpens() async {
        enum Failure: Error { case denied }
        let urls = ["a", "b", "existing", "failed"].map { URL(fileURLWithPath: "/tmp/\($0).ds3") }
        let first = NSObject()
        let second = NSObject()
        let other = NSObject()
        let opener = EditorLaunchDocumentOpener(arguments: ["Editor", "-toggle-color", "True"] + urls.map(\.path))
        var errors = 0
        await opener.openRequestedDocument(
            open: { url in
                switch url {
                case urls[0]: return first
                case urls[1]: return second
                case urls[2]: return nil
                default: throw Failure.denied
                }
            },
            reportError: { _ in errors += 1 })
        XCTAssertEqual(errors, 1)

        let wrong = await opener.claimNeutralPreview(for: urls[0], document: other)
        let correct = await opener.claimNeutralPreview(for: urls[0], document: first)
        let repeatClaim = await opener.claimNeutralPreview(for: urls[0], document: first)
        let secondClaim = await opener.claimNeutralPreview(for: urls[1], document: second)
        let existing = await opener.claimNeutralPreview(for: urls[2], document: other)
        let failed = await opener.claimNeutralPreview(for: urls[3], document: other)
        let untitled = await opener.claimNeutralPreview(for: nil, document: other)
        XCTAssertFalse(wrong)
        XCTAssertTrue(correct)
        XCTAssertFalse(repeatClaim)
        XCTAssertTrue(secondClaim)
        XCTAssertFalse(existing)
        XCTAssertFalse(failed)
        XCTAssertFalse(untitled)
    }

    func testTimedOutDocumentCannotApplyThePreferenceAfterOpenFinishes() async {
        let url = URL(fileURLWithPath: "/tmp/a.ds3")
        let document = NSObject()
        let opener = EditorLaunchDocumentOpener(arguments: ["Editor", "-toggle-color", "1", url.path])
        await opener.openRequestedDocument(
            open: { _ in
                let timedOut = await opener.claimNeutralPreview(
                    for: url, document: document, waitLimit: .milliseconds(1))
                XCTAssertFalse(timedOut)
                return document
            },
            reportError: { _ in XCTFail("Unexpected open failure") })
        let late = await opener.claimNeutralPreview(for: url, document: document)
        XCTAssertFalse(late)
    }

    func testUnrelatedTimeoutAndCancellationLeavePreferenceForMatchingWindow() async {
        let url = URL(fileURLWithPath: "/tmp/a.ds3")
        let document = NSObject()
        let unrelated = NSObject()
        let opener = EditorLaunchDocumentOpener(arguments: ["Editor", "-toggle-color", "1", url.path])
        await opener.openRequestedDocument(
            open: { _ in
                let timedOut = await opener.claimNeutralPreview(
                    for: url, document: unrelated, waitLimit: .milliseconds(1))
                XCTAssertFalse(timedOut)
                let claim = Task { await opener.claimNeutralPreview(for: url, document: document) }
                await Task.yield()
                claim.cancel()
                let cancelled = await claim.value
                XCTAssertFalse(cancelled)
                return document
            },
            reportError: { _ in XCTFail("Unexpected open failure") })
        let accepted = await opener.claimNeutralPreview(for: url, document: document)
        XCTAssertTrue(accepted)
    }
}
