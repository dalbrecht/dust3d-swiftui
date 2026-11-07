import Foundation
import XCTest

@testable import Dust3DEditor

final class EditorRigListCommandTests: XCTestCase {
    private enum FixtureFailure: LocalizedError {
        case missing, output
        var errorDescription: String? {
            switch self {
            case .missing: "template unavailable"
            case .output: "output unavailable"
            }
        }
    }

    func testOrdinaryLaunchAndLiteralArgumentsFallThroughWithoutIO() {
        for arguments in [
            [], ["editor"], ["editor", "model.ds3"], ["editor", "--open-document", "/tmp/model.ds3"],
            ["editor", "--write-recovery-copies", "123"], ["editor", "--", "-list-rigs"],
            ["editor", "--", "-list-rigs.ds3"],
        ] {
            XCTAssertNil(
                EditorRigListCommand.run(
                    arguments: arguments,
                    load: { _ in
                        XCTFail("Unexpected resource read")
                        return nil
                    },
                    stdout: { _ in XCTFail("Unexpected stdout") },
                    stderr: { _ in XCTFail("Unexpected stderr") }))
        }
    }

    func testMixedOrRepeatedRequestsFailBeforeReadingOrPublishing() {
        for options in [
            ["-list-rigs", "model.ds3"], ["-list-rigs", "-list-rigs"],
            ["--write-recovery-copies", "123", "-list-rigs"], ["-list-rigs", "--"],
        ] {
            var diagnostic = ""
            let result = EditorRigListCommand.run(
                arguments: ["editor"] + options,
                load: { _ in
                    XCTFail("Unexpected resource read")
                    return nil
                },
                stdout: { _ in XCTFail("Unexpected stdout") },
                stderr: { diagnostic += $0 })
            XCTAssertEqual(result, 2)
            XCTAssertTrue(diagnostic.contains("-list-rigs"))
        }
    }

    func testPublishesOneQtOrderedXMLDocumentAfterAllResourceReads() throws {
        let expected = ["Biped", "Quadruped", "Bird", "Fish", "Insect", "Snake", "Spider"]
        var reads: [String] = []
        var writes: [Data] = []
        let result = EditorRigListCommand.run(
            arguments: ["editor", "-list-rigs"],
            load: { type in
                reads.append(type)
                return Data(
                    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\r\n<rig type=\"\(type)\"><bone name=\"Root\"/></rig> \r\n"
                        .utf8)
            },
            stdout: { data in
                XCTAssertEqual(reads, expected)
                writes.append(data)
            },
            stderr: { _ in XCTFail("Unexpected stderr") })
        XCTAssertEqual(result, 0)
        let data = try XCTUnwrap(writes.first)
        XCTAssertEqual(writes.count, 1)
        let xml = try XMLDocument(data: data)
        XCTAssertEqual(xml.rootElement()?.name, "rigs")
        XCTAssertEqual(try xml.nodes(forXPath: "/rigs/rig/@type").compactMap(\.stringValue), expected)
        XCTAssertEqual(try xml.nodes(forXPath: "/rigs/rig/bone").count, expected.count)
    }

    func testDefaultLoaderListsAllBundledAuthoredRigsInQtOrder() throws {
        var writes: [Data] = []
        let result = EditorRigListCommand.run(
            arguments: ["editor", "-list-rigs"],
            stdout: { writes.append($0) },
            stderr: { XCTFail($0) })
        XCTAssertEqual(result, 0)
        XCTAssertEqual(writes.count, 1)
        let xml = try XMLDocument(data: XCTUnwrap(writes.first))
        XCTAssertEqual(xml.rootElement()?.name, "rigs")
        XCTAssertEqual(
            try xml.nodes(forXPath: "/rigs/rig/@type").compactMap(\.stringValue),
            ["Biped", "Quadruped", "Bird", "Fish", "Insect", "Snake", "Spider"])
        XCTAssertEqual(try xml.nodes(forXPath: "/rigs/rig[bone]").count, 7)
    }

    func testLateResourceFailureAndInvalidUTF8CannotPublishPartialXML() {
        for invalidUTF8 in [false, true] {
            var reads: [String] = []
            var diagnostic = ""
            let result = EditorRigListCommand.run(
                arguments: ["editor", "-list-rigs"],
                load: { type in
                    reads.append(type)
                    if type == "Spider" {
                        if invalidUTF8 { return Data([0xFF]) }
                        throw FixtureFailure.missing
                    }
                    return Data("<rig type=\"\(type)\"/>".utf8)
                },
                stdout: { _ in XCTFail("Partial output was published") },
                stderr: { diagnostic += $0 })
            XCTAssertEqual(result, 1)
            XCTAssertEqual(reads.count, 7)
            XCTAssertTrue(diagnostic.contains("Spider"))
            if !invalidUTF8 { XCTAssertTrue(diagnostic.contains("template unavailable")) }
        }
    }

    func testOutputFailureReportsNonzeroStatus() {
        var diagnostic = ""
        let result = EditorRigListCommand.run(
            arguments: ["editor", "-list-rigs"],
            load: { type in Data("<rig type=\"\(type)\"/>".utf8) },
            stdout: { _ in throw FixtureFailure.output },
            stderr: { diagnostic += $0 })
        XCTAssertEqual(result, 1)
        XCTAssertTrue(diagnostic.contains("output unavailable"))
    }
}
