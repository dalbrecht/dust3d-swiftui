import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DEditor

@MainActor
final class EditorHeadlessDS3SaveTests: XCTestCase {
    func testOrdinaryLaunchAndOtherHeadlessCommandsFallThrough() async {
        for arguments in [
            ["Editor"], ["Editor", "input.ds3", "-paste-xml", "fragment.xml"], ["Editor", "-list-rigs"],
            ["Editor", "--write-recovery-copies", "42"], ["Editor", "--", "-o"],
        ] {
            let result = await run(arguments)
            XCTAssertNil(result.status, arguments.joined(separator: " "))
            XCTAssertTrue(result.output.isEmpty)
            XCTAssertTrue(result.errors.isEmpty)
        }
    }

    func testMixedRigListAndSaveDeclinesBeforeReadingOrWriting() async throws {
        let directory = try temporaryDirectory()
        let source = directory.appendingPathComponent("source.ds3")
        let destination = directory.appendingPathComponent("output.ds3")
        let original = try archive().encoded()
        try original.write(to: source)
        let arguments = ["Editor", source.path, "-o", destination.path, "-list-rigs"]

        var diagnostics: [String] = []
        let listStatus = EditorRigListCommand.run(
            arguments: arguments,
            load: { _ in
                XCTFail("Mixed invocation read a rig template")
                return nil
            },
            stdout: { _ in XCTFail("Mixed invocation published a rig list") },
            stderr: { diagnostics.append($0) })
        XCTAssertEqual(listStatus, 2)
        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertTrue(diagnostics.first?.contains("-list-rigs") == true)

        let save = await run(arguments)
        XCTAssertNil(save.status)
        XCTAssertTrue(save.output.isEmpty)
        XCTAssertTrue(save.errors.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testSavePreservesSourceBytesAndContinuesAfterOneDestinationFails() async throws {
        let directory = try temporaryDirectory()
        let source = directory.appendingPathComponent("source.ds3")
        let first = directory.appendingPathComponent("first.ds3")
        let failed = directory.appendingPathComponent("missing/failed.ds3")
        let last = directory.appendingPathComponent("last.ds3")
        let bytes = try archive().encoded()
        try bytes.write(to: source)
        try Data("old destination".utf8).write(to: first)

        let result = await run([
            "Editor", "-o", first.path, source.path, "-toggle-color", "True", "-output", failed.path, "-o", last.path,
        ])

        XCTAssertEqual(result.status, 1)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertEqual(try Data(contentsOf: first), bytes)
        XCTAssertEqual(try Data(contentsOf: last), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: failed.path))
        XCTAssertEqual(result.output.count, 2)
        XCTAssertTrue(result.output.first?.contains(first.path) == true)
        XCTAssertTrue(result.output.last?.contains(last.path) == true)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertTrue(result.errors.first?.contains(failed.path) == true)
    }

    func testPasteIntoSourceOrEmptyDocumentBeforeSaving() async throws {
        let directory = try temporaryDirectory()
        let source = directory.appendingPathComponent("source.ds3")
        let xml = directory.appendingPathComponent("fragment.xml")
        let first = directory.appendingPathComponent("first.ds3")
        let second = directory.appendingPathComponent("second.ds3")
        let original = try archive()
        try original.encoded().write(to: source)
        try original.modelXML.write(to: xml)

        let result = await run([
            "Editor", "-paste-xml", xml.path, "-output", first.path, source.path, "-o", second.path,
        ])
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.errors.isEmpty)
        let firstBytes = try Data(contentsOf: first)
        XCTAssertEqual(try Data(contentsOf: second), firstBytes)
        let edited = try Dust3DDocument(data: firstBytes)
        let ids = try edited.editorContents().nodes.map(\.id)
        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(Set(ids).count, 2)
        XCTAssertTrue(ids.contains("a"))
        XCTAssertEqual(edited.asset(named: "future.bin"), original.asset(named: "future.bin"))
        XCTAssertEqual(try Data(contentsOf: source), original.encoded())
        XCTAssertEqual(try Data(contentsOf: xml), original.modelXML)

        let fromXML = directory.appendingPathComponent("from-xml.ds3")
        let xmlOnly = await run(["Editor", "-o", fromXML.path, "-paste-xml", xml.path])
        XCTAssertEqual(xmlOnly.status, 0)
        let created = try Dust3DDocument(data: Data(contentsOf: fromXML))
        XCTAssertEqual(try created.editorContents().nodes.count, 1)
    }

    func testInvalidInputLeavesEveryDestinationUntouched() async throws {
        let directory = try temporaryDirectory()
        let source = directory.appendingPathComponent("source.ds3")
        let xml = directory.appendingPathComponent("fragment.xml")
        let existing = directory.appendingPathComponent("existing.ds3")
        let absent = directory.appendingPathComponent("absent.ds3")
        let original = Data("previous destination".utf8)
        try original.write(to: existing)
        try Data("invalid archive".utf8).write(to: source)
        let invalidArchive = await run(["Editor", source.path, "-o", existing.path, "-o", absent.path])
        XCTAssertEqual(invalidArchive.status, 1)
        XCTAssertTrue(invalidArchive.errors.first?.contains(source.path) == true)

        try archive().encoded().write(to: source)
        try Data("<canvas><nodes>".utf8).write(to: xml)
        let invalidXML = await run([
            "Editor", source.path, "-o", existing.path, "-paste-xml", xml.path, "-o", absent.path,
        ])
        XCTAssertEqual(invalidXML.status, 1)
        XCTAssertTrue(invalidXML.errors.first?.contains(xml.path) == true)
        XCTAssertTrue(invalidArchive.output.isEmpty && invalidXML.output.isEmpty)
        XCTAssertEqual(try Data(contentsOf: existing), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: absent.path))
    }

    func testRejectsInvalidAssociationsBeforeWritingAnyDestination() async throws {
        let directory = try temporaryDirectory()
        let source = directory.appendingPathComponent("source.ds3")
        let output = directory.appendingPathComponent("output.ds3")
        let bytes = try archive().encoded()
        try bytes.write(to: source)
        let arguments = ["Editor", source.path, "-o", output.path]
        let tooMany = (0..<64).flatMap { ["-o", directory.appendingPathComponent("\($0).ds3").path] }
        for invalid in [
            ["Editor", "-o", output.path], arguments + ["-o"], arguments + ["another.ds3"],
            arguments + ["-output", "geometry.obj"], arguments + ["-o", output.path],
            arguments + ["-o", source.path], arguments + tooMany,
            arguments + ["-paste-xml", "one.xml", "-paste-xml", "two.xml"],
        ] {
            let result = await run(invalid)
            XCTAssertEqual(result.status, 2, invalid.joined(separator: " "))
            XCTAssertTrue(result.output.isEmpty)
            XCTAssertFalse(result.errors.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
            XCTAssertEqual(try Data(contentsOf: source), bytes)
        }
    }

    func testRejectsHardLinkedSourceAndSymlinkedDestinationsBeforeWriting() async throws {
        let directory = try temporaryDirectory()
        let source = directory.appendingPathComponent("source.ds3")
        let first = directory.appendingPathComponent("first.ds3")
        let hardLink = directory.appendingPathComponent("hard.ds3")
        let symlink = directory.appendingPathComponent("symbolic.ds3")
        let bytes = try archive().encoded()
        try bytes.write(to: source)
        try FileManager.default.linkItem(at: source, to: hardLink)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: source)
        for alias in [hardLink, symlink] {
            let result = await run(["Editor", source.path, "-o", first.path, "-o", alias.path])
            XCTAssertEqual(result.status, 2)
            XCTAssertTrue(result.output.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
            XCTAssertEqual(try Data(contentsOf: source), bytes)
        }
    }

    private func run(_ arguments: [String]) async -> (status: Int32?, output: [String], errors: [String]) {
        var output: [String] = []
        var errors: [String] = []
        let status = await EditorHeadlessDS3SaveCommand.run(
            arguments: arguments, stdout: { output.append($0) }, stderr: { errors.append($0) })
        return (status, output, errors)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func archive() throws -> Dust3DDocument {
        let model = Data(
            "<canvas><nodes><node id='a' partId='p' x='0' y='0' z='0' radius='.1'/></nodes><parts><part id='p'/></parts><components><component id='c' linkDataType='partId' linkData='p'/></components></canvas>"
                .utf8)
        let asset = Data([0, 255, 17, 42])
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(model.count)'/><asset name='future.bin' offset='\(model.count)' size='\(asset.count)'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        let bytes =
            Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
            + model + asset
        return try Dust3DDocument(data: bytes)
    }
}
