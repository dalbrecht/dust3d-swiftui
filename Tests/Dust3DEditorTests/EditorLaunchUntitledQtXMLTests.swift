import Foundation
import XCTest

@testable import Dust3DEditor

@MainActor
final class EditorLaunchUntitledQtXMLTests: XCTestCase {
    func testXMLOnlyUsesOneExactUntitledDocumentWithDefaultColors() async throws {
        let xml = URL(fileURLWithPath: "/tmp/startup-fragment.xml")
        let data = Data("<canvas/>".utf8)
        let document = NSObject()
        let otherDocument = NSObject()
        let arguments = ["Editor", "-paste-xml", xml.path, "-toggle-color", "true"]
        XCTAssertEqual(try EditorLaunchRequest(arguments: arguments), .untitledPaste(xml))
        let opener = EditorLaunchDocumentOpener(arguments: arguments)
        XCTAssertTrue(opener.shouldSuppressUntitledDocument)
        var created = 0
        var reads: [URL] = []
        var displayed = 0
        for _ in 0..<2 {
            await opener.openRequestedDocument(
                readPaste: {
                    reads.append($0)
                    return data
                },
                open: { _ in
                    XCTFail("XML-only launch tried to open a file document")
                    return nil
                },
                createUntitled: {
                    created += 1
                    return document
                },
                displayNew: { candidate in
                    displayed += 1
                    XCTAssertTrue(candidate === document)
                    XCTAssertNil(opener.claimStartupPaste(for: nil, document: otherDocument, isEdited: false))
                    XCTAssertNil(opener.claimStartupPaste(for: xml, document: document, isEdited: false))
                    XCTAssertEqual(opener.claimStartupPaste(for: nil, document: document, isEdited: false), data)
                    XCTAssertNil(opener.claimStartupPaste(for: nil, document: document, isEdited: false))
                },
                reportError: { XCTFail("Unexpected startup error: \($0)") })
        }
        XCTAssertEqual(created, 1)
        XCTAssertEqual(displayed, 1)
        XCTAssertEqual(reads, [xml])
        let neutral = await opener.claimNeutralPreview(for: nil, document: document)
        XCTAssertFalse(neutral)
    }

    func testEditedUntitledDocumentRetiresItsPendingPaste() async {
        let opener = EditorLaunchDocumentOpener(arguments: ["Editor", "-paste-xml", "/tmp/edits.xml"])
        let document = NSObject()
        await opener.openRequestedDocument(
            readPaste: { _ in Data("<canvas/>".utf8) },
            open: { _ in nil },
            createUntitled: { document },
            displayNew: { _ in
                XCTAssertNil(opener.claimStartupPaste(for: nil, document: document, isEdited: true))
                XCTAssertNil(opener.claimStartupPaste(for: nil, document: document, isEdited: false))
            },
            reportError: { XCTFail("Unexpected startup error: \($0)") })
    }

    func testUnreadableXMLReportsFailureAndLeavesOneBlankUntitledDocument() async {
        let opener = EditorLaunchDocumentOpener(arguments: ["Editor", "-paste-xml", "/tmp/missing.xml"])
        let document = NSObject()
        var errors: [CocoaError.Code] = []
        var displayed = 0
        await opener.openRequestedDocument(
            readPaste: { _ in throw CocoaError(.fileReadNoSuchFile) },
            open: { _ in
                XCTFail("XML-only launch tried to open a file document")
                return nil
            },
            createUntitled: { document },
            displayNew: { candidate in
                displayed += 1
                XCTAssertTrue(candidate === document)
                XCTAssertNil(opener.claimStartupPaste(for: nil, document: candidate, isEdited: false))
            },
            reportError: { errors.append(($0 as? CocoaError)?.code ?? .fileReadUnknown) })
        XCTAssertEqual(errors, [.fileReadNoSuchFile])
        XCTAssertEqual(displayed, 1)
    }
}
