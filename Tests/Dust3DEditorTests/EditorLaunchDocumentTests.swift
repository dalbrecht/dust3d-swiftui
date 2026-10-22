import Foundation
import XCTest

@testable import Dust3DEditor

final class EditorLaunchDocumentTests: XCTestCase {
    func testParsesExplicitAbsoluteDocumentWithoutInterpretingSystemArguments() throws {
        XCTAssertEqual(try EditorLaunchRequest(arguments: ["Editor", "-ApplePersistenceIgnoreState", "YES"]), .none)
        let path = "/tmp/QA model.DS3"
        XCTAssertEqual(
            try EditorLaunchRequest(arguments: ["Editor", "--open-document", path]),
            .open(URL(fileURLWithPath: path)))
    }

    func testRejectsMissingDuplicateRelativeAndInvalidDocumentArguments() {
        for arguments in [
            ["Editor", "--open-document"],
            ["Editor", "--open-document", "/tmp/a.ds3", "--open-document", "/tmp/b.ds3"],
            ["Editor", "--open-document", "relative.ds3"],
            ["Editor", "--open-document", "https://example.com/a.ds3"],
            ["Editor", "--open-document", "/tmp/a.txt"],
            ["Editor", "--open-document", "/tmp/a\0.ds3"],
            ["Editor", "--open-document", "/" + String(repeating: "x", count: 4096) + ".ds3"],
        ] {
            XCTAssertThrowsError(try EditorLaunchRequest(arguments: arguments)) {
                XCTAssertEqual($0 as? EditorLaunchError, .invalidDocumentArgument)
            }
        }
    }

    @MainActor
    func testOpensThroughInjectedDocumentSystemOnceAndSuppressesStartupPicker() async {
        let opener = EditorLaunchDocumentOpener(arguments: ["Editor", "--open-document", "/tmp/a.ds3"])
        XCTAssertTrue(opener.shouldSuppressUntitledDocument)
        var opened: [URL] = []
        var errors: [Error] = []
        for _ in 0..<2 {
            await opener.openRequestedDocument(
                open: { url in
                    opened.append(url)
                    await opener.openRequestedDocument(
                        open: { _ in XCTFail("Reentrant request opened twice") },
                        reportError: { _ in XCTFail("Reentrant request reported an error") })
                }, reportError: { errors.append($0) })
        }
        XCTAssertEqual(opened, [URL(fileURLWithPath: "/tmp/a.ds3")])
        XCTAssertTrue(errors.isEmpty)
    }

    @MainActor
    func testPreservesOriginalOpenFailureAndReportsInvalidArgumentsWithoutOpening() async {
        enum OpenFailure: Error { case denied }
        let opener = EditorLaunchDocumentOpener(arguments: ["Editor", "--open-document", "/tmp/a.ds3"])
        var errors: [Error] = []
        await opener.openRequestedDocument(open: { _ in throw OpenFailure.denied }, reportError: { errors.append($0) })
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors.first is OpenFailure)
        let invalid = EditorLaunchDocumentOpener(arguments: ["Editor", "--open-document"])
        XCTAssertTrue(invalid.shouldSuppressUntitledDocument)
        await invalid.openRequestedDocument(
            open: { _ in XCTFail("Invalid path opened") }, reportError: { errors.append($0) })
        XCTAssertEqual(errors.last as? EditorLaunchError, .invalidDocumentArgument)
        XCTAssertTrue(errors.last?.localizedDescription.contains("--open-document") == true)
        let ordinary = EditorLaunchDocumentOpener(arguments: ["Editor"])
        XCTAssertFalse(ordinary.shouldSuppressUntitledDocument)
        await ordinary.openRequestedDocument(
            open: { _ in XCTFail("Ordinary launch opened a document") },
            reportError: { _ in XCTFail("Unexpected error") })
    }
}
