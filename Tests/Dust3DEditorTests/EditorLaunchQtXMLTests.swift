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

    func testFailedStartupPasteStillOpensAndDisplaysEveryRequestedDocument() async {
        enum FragmentFailure: Error { case unreadable }
        let paths = ["/tmp/first.ds3", "/tmp/second.ds3"]
        let urls = paths.map { URL(fileURLWithPath: $0) }
        let fragment = "/tmp/fragment.xml"

        for canRead in [false, true] {
            let opener = EditorLaunchDocumentOpener(arguments: ["Editor"] + paths + ["-paste-xml", fragment])
            XCTAssertTrue(opener.hasPasteRequest)
            let documents = [NSObject(), NSObject()]
            var opened: [URL] = []
            var displayed: [ObjectIdentifier] = []
            var failures: [Error] = []
            var readCount = 0
            await opener.openRequestedDocument(
                readPaste: { url in
                    XCTAssertEqual(url.path, fragment)
                    readCount += 1
                    if !canRead { throw FragmentFailure.unreadable }
                    return Data("invalid snapshot XML".utf8)
                },
                open: { url in
                    opened.append(url)
                    return urls.firstIndex(of: url).map { documents[$0] }
                },
                displayNew: { displayed.append(ObjectIdentifier($0)) },
                reportError: {
                    XCTAssertEqual(displayed.count, documents.count)
                    failures.append($0)
                })

            XCTAssertEqual(readCount, 1)
            XCTAssertEqual(opened, urls)
            XCTAssertEqual(displayed, documents.map(ObjectIdentifier.init))
            XCTAssertEqual(failures.count, 1)
            if !canRead { XCTAssertEqual(failures.first as? FragmentFailure, .unreadable) }
            for (url, document) in zip(urls, documents) {
                XCTAssertFalse(opener.hasStartupPaste(for: url))
                XCTAssertNil(opener.claimStartupPaste(for: url, document: document, isEdited: false))
            }
        }
    }
}
