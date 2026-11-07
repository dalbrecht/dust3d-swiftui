import Foundation
import XCTest

@testable import Dust3DEditor

final class EditorLaunchDocumentTests: XCTestCase {
    func testParsesExplicitAbsoluteDocumentWithoutInterpretingSystemArguments() throws {
        XCTAssertEqual(try EditorLaunchRequest(arguments: ["Editor", "-ApplePersistenceIgnoreState", "YES"]), .none)
        let path = "/tmp/QA model.DS3"
        XCTAssertEqual(
            try EditorLaunchRequest(arguments: ["Editor", "--open-document", path]),
            .open([URL(fileURLWithPath: path)]))
    }

    func testRejectsMissingDuplicateRelativeAndInvalidDocumentArguments() {
        for arguments in [
            ["Editor", "--open-document"],
            ["Editor", "--open-document", "/tmp/a.ds3", "--open-document", "/tmp/./a.ds3"],
            ["Editor", "/tmp/a.ds3", "--open-document", "/tmp/b.txt"],
            ["Editor", "https://example.com/a.ds3"],
            ["Editor"] + (0...64).map { "/tmp/\($0).ds3" },
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

    func testMixedInputsKeepOrderAndSkipPlatformOptionValues() throws {
        let arguments = [
            "Editor", "-psn_0_12345", "-ApplePersistenceIgnoreState", "YES",
            "relative.DS3", "--open-document", "/tmp/second.ds3",
            "--open-document", "/tmp/third.ds3", "--", "-paste-xml.ds3", "-toggle-color.ds3",
        ]
        let paths = ["relative.DS3", "/tmp/second.ds3", "/tmp/third.ds3", "-paste-xml.ds3", "-toggle-color.ds3"]
        XCTAssertEqual(
            try EditorLaunchRequest(arguments: arguments),
            .open(paths.map { URL(fileURLWithPath: $0).standardizedFileURL }))
        XCTAssertEqual(
            try EditorLaunchRequest(arguments: ["Editor", "--unknown", "/tmp/operand.ds3"]),
            .none)
        XCTAssertEqual(
            try EditorLaunchRequest(
                arguments: ["Editor", "--unknown", "/tmp/operand.ds3", "--open-document", "/tmp/explicit.ds3"]),
            .open([URL(fileURLWithPath: "/tmp/explicit.ds3")]))
    }

    @MainActor
    func testInvalidBatchAndUnsupportedQtOptionsNeverOpenAnyDocument() async {
        for (arguments, expected) in [
            (
                ["Editor", "/tmp/first.ds3", "--open-document", "relative.ds3"],
                EditorLaunchError.invalidDocumentArgument
            ),
            (["Editor", "/tmp/first.ds3", "-o", "/tmp/result.obj"], .unsupportedExportArgument),
            (["Editor", "/tmp/first.ds3", "-output", "/tmp/result.obj"], .unsupportedExportArgument),
            (["Editor", "/tmp/first.ds3", "-paste-xml", "/tmp/edits.xml"], .unsupportedPasteArgument),
            (["Editor", "/tmp/first.ds3", "-toggle-color"], .invalidColorArgument),
        ] {
            let opener = EditorLaunchDocumentOpener(arguments: arguments)
            XCTAssertTrue(opener.shouldSuppressUntitledDocument)
            var errors: [EditorLaunchError] = []
            await opener.openRequestedDocument(
                open: { _ in
                    XCTFail("A rejected batch must not open any of its paths")
                    return nil
                },
                reportError: { error in
                    if let error = error as? EditorLaunchError { errors.append(error) }
                })
            XCTAssertEqual(errors, [expected])
        }
    }

    @MainActor
    func testOpensEveryValidatedPathOnceDespiteReentryAndIndividualFailure() async {
        enum OpenFailure: Error { case denied }
        let paths = ["/tmp/first.ds3", "/tmp/second.ds3", "/tmp/third.ds3"]
        let opener = EditorLaunchDocumentOpener(arguments: ["Editor"] + paths)
        XCTAssertTrue(opener.shouldSuppressUntitledDocument)
        var opened: [String] = []
        var errors: [Error] = []
        let report: @MainActor (Error) -> Void = { errors.append($0) }
        await opener.openRequestedDocument(
            open: { url in
                opened.append(url.path)
                await opener.openRequestedDocument(
                    open: { _ in
                        XCTFail("Reentrant dispatch")
                        return nil
                    }, reportError: report)
                if url.path == paths[1] { throw OpenFailure.denied }
                return nil
            }, reportError: report)
        await opener.openRequestedDocument(
            open: { _ in
                XCTFail("Duplicate lifecycle callback")
                return nil
            }, reportError: report)
        XCTAssertEqual(opened, paths)
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors.first is OpenFailure)
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
                        open: { _ in
                            XCTFail("Reentrant request opened twice")
                            return nil
                        },
                        reportError: { _ in XCTFail("Reentrant request reported an error") })
                    return nil
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
            open: { _ in
                XCTFail("Invalid path opened")
                return nil
            }, reportError: { errors.append($0) })
        XCTAssertEqual(errors.last as? EditorLaunchError, .invalidDocumentArgument)
        XCTAssertTrue(errors.last?.localizedDescription.contains("--open-document") == true)
        let ordinary = EditorLaunchDocumentOpener(arguments: ["Editor"])
        XCTAssertFalse(ordinary.shouldSuppressUntitledDocument)
        await ordinary.openRequestedDocument(
            open: { _ in
                XCTFail("Ordinary launch opened a document")
                return nil
            },
            reportError: { _ in XCTFail("Unexpected error") })
    }
}
