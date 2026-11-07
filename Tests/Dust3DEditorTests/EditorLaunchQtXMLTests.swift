import Foundation
import XCTest

@testable import Dust3DEditor

@MainActor
final class EditorLaunchQtXMLTests: XCTestCase {
    func testReadsOnceBeforeOpeningAndClaimsOnlyExactNewCleanDocuments() async throws {
        let urls = ["first", "already-open", "dirty", "last"].map { URL(fileURLWithPath: "/tmp/\($0).ds3") }
        let xml = URL(fileURLWithPath: "/tmp/edits.xml")
        let data = Data("<canvas/>".utf8)
        let documents = urls.map { _ in NSObject() }
        let opener = EditorLaunchDocumentOpener(
            arguments: ["Editor", "-paste-xml", xml.path, "-toggle-color", "true"] + urls.map(\.path))
        XCTAssertTrue(opener.shouldSuppressUntitledDocument)
        var readURLs: [URL] = []
        var openedURLs: [URL] = []
        var shown: [Int] = []
        await opener.openRequestedDocument(
            readPaste: {
                readURLs.append($0)
                return data
            },
            open: { url in
                XCTAssertEqual(readURLs, [xml])
                openedURLs.append(url)
                let index = try XCTUnwrap(urls.firstIndex(of: url))
                return index == 1 ? nil : documents[index]
            },
            displayNew: { document in
                guard let index = documents.firstIndex(where: { $0 === document }) else {
                    return XCTFail("A different native document was displayed")
                }
                shown.append(index)
                let url = urls[index]
                XCTAssertNil(opener.claimStartupPaste(for: url, document: NSObject(), isEdited: false))
                let claimed = opener.claimStartupPaste(for: url, document: document, isEdited: index == 2)
                XCTAssertEqual(claimed, index == 2 ? nil : data)
                XCTAssertNil(opener.claimStartupPaste(for: url, document: document, isEdited: false))
            },
            reportError: { XCTFail("Unexpected open failure: \($0)") })
        XCTAssertEqual(openedURLs, urls)
        XCTAssertEqual(shown, [0, 2, 3])
        XCTAssertNil(opener.claimStartupPaste(for: urls[1], document: documents[1], isEdited: false))
        XCTAssertNil(opener.claimStartupPaste(for: nil, document: documents[0], isEdited: false))
        let neutral = await opener.claimNeutralPreview(for: urls[0], document: documents[0])
        XCTAssertTrue(neutral)
    }

    func testMissingInitialWindowCannotClaimAfterDeadline() async throws {
        let url = URL(fileURLWithPath: "/tmp/a.ds3")
        let document = NSObject()
        let opener = EditorLaunchDocumentOpener(
            arguments: ["Editor", url.path, "-paste-xml", "/tmp/edits.xml"])
        await opener.openRequestedDocument(
            readPaste: { _ in Data("<canvas/>".utf8) },
            open: { _ in document },
            displayNew: { _ in
                XCTAssertTrue(opener.hasStartupPaste(for: url))
                XCTAssertNil(opener.claimStartupPaste(for: url, document: nil, isEdited: false))
            },
            reportError: { XCTFail("Unexpected open failure: \($0)") })
        try await Task.sleep(for: .seconds(2))
        XCTAssertFalse(opener.hasStartupPaste(for: url))
        XCTAssertNil(opener.claimStartupPaste(for: url, document: document, isEdited: false))
    }

    func testMalformedPreflightNeverOpensOrDisplaysAnyDocument() async {
        let opener = EditorLaunchDocumentOpener(
            arguments: ["Editor", "/tmp/a.ds3", "/tmp/b.ds3", "-paste-xml", "/tmp/edits.xml"])
        var errors = 0
        await opener.openRequestedDocument(
            readPaste: { _ in Data("not XML".utf8) },
            open: { _ in
                XCTFail("Malformed preflight opened a document")
                return nil
            },
            displayNew: { _ in XCTFail("Malformed preflight displayed a document") },
            reportError: { _ in errors += 1 })
        XCTAssertEqual(errors, 1)
    }
}
