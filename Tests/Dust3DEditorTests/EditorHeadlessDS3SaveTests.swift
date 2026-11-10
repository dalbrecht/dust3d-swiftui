import Dust3DDocument
import Dust3DKit
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

    func testMixedRigListAndSaveListsWithoutWritingDestination() async throws {
        let directory = try temporaryDirectory()
        let source = directory.appendingPathComponent("source.ds3")
        let destination = directory.appendingPathComponent("output.ds3")
        let original = try archive().encoded()
        try original.write(to: source)
        let arguments = ["Editor", source.path, "-o", destination.path, "-list-rigs"]

        var output: [Data] = []
        let listStatus = EditorRigListCommand.run(
            arguments: arguments,
            load: { type in Data("<rig type=\"\(type)\"/>".utf8) },
            stdout: { output.append($0) },
            stderr: { XCTFail($0) })
        XCTAssertEqual(listStatus, 0)
        XCTAssertEqual(output.count, 1)

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

    func testHeadlessQtPasteSettlesOnlyANewDocumentsOrigin() async throws {
        let directory = try temporaryDirectory()
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Dust3DKitTests/Fixtures/Capsule.ds3")
        let source = try Data(contentsOf: fixture)
        let fragment = directory.appendingPathComponent("fragment.xml")
        let xml = try Dust3DDocument(data: source).modelXML
        try xml.write(to: fragment)
        let existing = directory.appendingPathComponent("existing-source.ds3")
        let existingBytes = Dust3DDocument.emptyArchive()
        try existingBytes.write(to: existing)

        for (name, input, expectedZ) in [
            ("new", [String](), 1.0),
            ("existing", [existing.path], 0.5),
        ] {
            let archive = directory.appendingPathComponent(name + ".ds3")
            let geometry = directory.appendingPathComponent(name + ".obj")
            let result = await run(
                ["Editor"] + input + ["-paste-xml", fragment.path, "-o", archive.path, "-o", geometry.path],
                geometryEncoder: NativeGeometryExportEncoder())
            XCTAssertEqual(result.status, 0, result.errors.joined())
            let saved = try Dust3DDocument(data: Data(contentsOf: archive))
            let canvas = try XCTUnwrap(XMLDocument(data: saved.modelXML).rootElement())
            let z = try XCTUnwrap(canvas.attribute(forName: "originZ")?.stringValue.flatMap(Double.init))
            XCTAssertEqual(z, expectedZ, accuracy: 1e-12)
            XCTAssertTrue(FileManager.default.fileExists(atPath: geometry.path))
        }
        XCTAssertEqual(try Data(contentsOf: existing), existingBytes)
        XCTAssertEqual(try Data(contentsOf: fixture), source)
        XCTAssertEqual(try Data(contentsOf: fragment), xml)
    }

    func testPasteIntoSourceOrEmptyDocumentBeforeSaving() async throws {
        let directory = try temporaryDirectory()
        let source = directory.appendingPathComponent("source.ds3")
        let xml = directory.appendingPathComponent("Modèle fragment.dust3d-fragment")
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

    func testRepeatedPasteUsesLastFragmentAndProtectsSupersededInput() async throws {
        let directory = try temporaryDirectory()
        let ignored = directory.appendingPathComponent("ignored.ds3")
        let final = directory.appendingPathComponent("final.xml")
        let output = directory.appendingPathComponent("output.ds3")
        let original = try archive()
        try original.encoded().write(to: ignored)
        try original.modelXML.write(to: final)
        let arguments = ["Editor", "-paste-xml", ignored.path, "-paste-xml", final.path]
        let saved = await run(arguments + ["-o", output.path])
        XCTAssertEqual(saved.status, 0)
        let document = try Dust3DDocument(data: Data(contentsOf: output))
        XCTAssertEqual(try document.editorContents().nodes.count, 1)
        let refused = await run(arguments + ["-o", ignored.path])
        XCTAssertEqual(refused.status, 2)
        XCTAssertEqual(try Data(contentsOf: ignored), original.encoded())
    }

    func testInvalidInputLeavesEveryDestinationUntouched() async throws {
        let directory = try temporaryDirectory()
        let source = directory.appendingPathComponent("source.ds3")
        let xml = directory.appendingPathComponent("invalid-fragment")
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
        XCTAssertTrue(invalidXML.errors.first?.contains("The document contains invalid or unsupported XML.") == true)

        try Data("<canvas><nodes><node id='a' partId='p'/></nodes></canvas>".utf8).write(to: xml)
        let invalidGraph = await run([
            "Editor", source.path, "-o", existing.path, "-paste-xml", xml.path, "-o", absent.path,
        ])
        XCTAssertEqual(invalidGraph.status, 1)
        XCTAssertTrue(invalidGraph.errors.first?.contains(xml.path) == true)
        XCTAssertTrue(
            invalidGraph.errors.first?.contains("The document contains invalid node, part, or edge data.") == true)
        XCTAssertTrue(invalidGraph.output.isEmpty)
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
            arguments + ["-output", "unsupported.txt"], arguments + ["-o", output.path],
            arguments + ["-o", source.path], arguments + tooMany,
            arguments + ["-paste-xml", "one.xml", "-paste-xml"],
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

    func testHeadlessFBXDefaultsToTexturesAndOffersExplicitGeometry() async throws {
        let directory = try temporaryDirectory()
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Dust3DKitTests/Fixtures/Capsule.ds3")
        let geometry = directory.appendingPathComponent("geometry.fbx")
        let textured = directory.appendingPathComponent("textured.FBX")
        let alias = directory.appendingPathComponent("alias.fbx")
        let original = try Data(contentsOf: fixture)

        let result = await run(
            [
                "Editor", fixture.path, "-o", textured.path, "--geometry-fbx", geometry.path, "--textured-fbx",
                alias.path,
            ], geometryEncoder: NativeGeometryExportEncoder())
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output.count, 3)
        XCTAssertTrue(result.errors.isEmpty)
        let uvNode = Data("LayerElementUV".utf8)
        XCTAssertNotNil(try Data(contentsOf: textured).range(of: uvNode))
        XCTAssertNil(try Data(contentsOf: geometry).range(of: uvNode))
        XCTAssertEqual(try Data(contentsOf: alias), try Data(contentsOf: textured))
        XCTAssertEqual(try Data(contentsOf: fixture), original)

        let invalid = await run(
            ["Editor", fixture.path, "--geometry-fbx", geometry.path, "-o", geometry.path],
            geometryEncoder: NativeGeometryExportEncoder())
        XCTAssertEqual(invalid.status, 2)
        XCTAssertTrue(invalid.output.isEmpty)
        XCTAssertNil(try Data(contentsOf: geometry).range(of: uvNode))
    }

    func testDefaultEncoderExportsGeometryAndContinuesAfterUnavailableGLB() async throws {
        let directory = try temporaryDirectory()
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Dust3DKitTests/Fixtures/Capsule.ds3")
        let original = try Data(contentsOf: source)
        let obj = directory.appendingPathComponent("model.obj")
        let glb = directory.appendingPathComponent("existing.glb")
        let fbx = directory.appendingPathComponent("model.fbx")
        let copy = directory.appendingPathComponent("copy.ds3")
        let previousGLB = Data("previous GLB".utf8)
        try previousGLB.write(to: glb)
        var messages: [String] = []
        var errors: [String] = []

        let status = await EditorHeadlessDS3SaveCommand.run(
            arguments: [
                "Editor", source.path, "-o", obj.path, "-o", glb.path, "--geometry-fbx", fbx.path, "-o", copy.path,
            ],
            stdout: { messages.append($0) }, stderr: { errors.append($0) })

        XCTAssertEqual(status, 1)
        XCTAssertEqual(messages.count, 3)
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors.first?.contains(glb.path) == true)
        XCTAssertTrue(
            try String(contentsOf: obj, encoding: .utf8).split(separator: "\n").contains {
                $0.hasPrefix("f ")
            })
        XCTAssertTrue(try Data(contentsOf: fbx).starts(with: "Kaydara FBX Binary".utf8))
        XCTAssertEqual(try Data(contentsOf: glb), previousGLB)
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(try Data(contentsOf: copy), original)
    }

    func testUnavailableGeometryLeavesExistingFilesAndContinuesInOrder() async throws {
        let directory = try temporaryDirectory()
        let source = directory.appendingPathComponent("source.ds3")
        let first = directory.appendingPathComponent("first.ds3")
        let obj = directory.appendingPathComponent("geometry.obj")
        let glb = directory.appendingPathComponent("geometry.glb")
        let last = directory.appendingPathComponent("last.ds3")
        let original = try archive().encoded()
        let previous = Data("previous output".utf8)
        try original.write(to: source)
        try previous.write(to: obj)
        try previous.write(to: glb)

        var messages: [String] = []
        let status = await EditorHeadlessDS3SaveCommand.run(
            arguments: ["Editor", source.path, "-o", first.path, "-o", obj.path, "-o", glb.path, "-o", last.path],
            geometryEncoder: nil, stdout: { messages.append($0) }, stderr: { messages.append($0) })

        XCTAssertEqual(status, 1)
        XCTAssertEqual(try Data(contentsOf: first), original)
        XCTAssertEqual(try Data(contentsOf: last), original)
        XCTAssertEqual(try Data(contentsOf: obj), previous)
        XCTAssertEqual(try Data(contentsOf: glb), previous)
        XCTAssertEqual(messages.count, 4)
        for (message, destination) in zip(messages, [first, obj, glb, last]) {
            XCTAssertTrue(message.contains(destination.path), message)
        }
        XCTAssertEqual(messages.filter { $0.localizedCaseInsensitiveContains("unavailable") }.count, 2)
    }

    func testMixedOutputsUseOneCapturedArchiveAndContinueAfterEncoderFailure() async throws {
        let directory = try temporaryDirectory()
        let source = directory.appendingPathComponent("source.ds3")
        let obj = directory.appendingPathComponent("geometry.obj")
        let fbx = directory.appendingPathComponent("geometry.fbx")
        let glb = directory.appendingPathComponent("geometry.glb")
        let saved = directory.appendingPathComponent("output.ds3")
        let original = try archive().encoded()
        let replacement = Dust3DDocument.emptyArchive()
        let previous = Data("previous OBJ".utf8)
        try original.write(to: source)
        try previous.write(to: obj)
        let encoder = FakeGeometryEncoder(source: source, replacement: replacement)

        let result = await run(
            ["Editor", source.path, "-o", obj.path, "-o", fbx.path, "-o", glb.path, "-o", saved.path],
            geometryEncoder: encoder)

        XCTAssertEqual(result.status, 1)
        XCTAssertEqual(result.errors.count, 2)
        XCTAssertTrue(result.errors.first?.contains(obj.path) == true)
        XCTAssertTrue(result.errors.last?.contains(glb.path) == true)
        XCTAssertEqual(result.output.count, 2)
        XCTAssertTrue(result.output.first?.contains(fbx.path) == true)
        XCTAssertTrue(result.output.last?.contains(saved.path) == true)
        XCTAssertEqual(try Data(contentsOf: source), replacement)
        XCTAssertEqual(try Data(contentsOf: obj), previous)
        XCTAssertEqual(try Data(contentsOf: fbx), Data("inert FBX".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: glb.path))
        XCTAssertEqual(try Data(contentsOf: saved), original)
        let calls = await encoder.calls
        XCTAssertEqual(calls.map(\.format), [.obj, .fbxTextured])
        XCTAssertEqual(calls.map(\.archive), [original, original])
    }

    func testMixedPreflightRejectsHardLinkToXMLAndCrossFormatOutputAlias() async throws {
        let directory = try temporaryDirectory()
        let source = directory.appendingPathComponent("source.ds3")
        let xml = directory.appendingPathComponent("fragment.xml")
        let saved = directory.appendingPathComponent("saved.ds3")
        let obj = directory.appendingPathComponent("geometry.obj")
        let fbx = directory.appendingPathComponent("geometry.fbx")
        let original = try archive()
        try original.encoded().write(to: source)
        try original.modelXML.write(to: xml)
        let encoder = FakeGeometryEncoder(source: source, replacement: Data())
        let arguments = ["Editor", source.path, "-paste-xml", xml.path, "-o", saved.path, "-o", obj.path]
        try FileManager.default.linkItem(at: xml, to: obj)

        let inputAlias = await run(arguments, geometryEncoder: encoder)
        XCTAssertEqual(inputAlias.status, 2)
        XCTAssertTrue(inputAlias.output.isEmpty)

        try FileManager.default.removeItem(at: obj)
        let previous = Data("previous output".utf8)
        try previous.write(to: obj)
        try FileManager.default.linkItem(at: obj, to: fbx)
        let outputAlias = await run(arguments + ["-o", fbx.path], geometryEncoder: encoder)
        XCTAssertEqual(outputAlias.status, 2)
        XCTAssertTrue(outputAlias.output.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: saved.path))
        XCTAssertEqual(try Data(contentsOf: xml), original.modelXML)
        XCTAssertEqual(try Data(contentsOf: obj), previous)
        XCTAssertEqual(try Data(contentsOf: fbx), previous)
        let calls = await encoder.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testXMLOnlyMixedBatchSucceedsWithInertGeometryEncoder() async throws {
        let directory = try temporaryDirectory()
        let xml = directory.appendingPathComponent("fragment.xml")
        let fbx = directory.appendingPathComponent("geometry.fbx")
        let saved = directory.appendingPathComponent("saved.ds3")
        try archive().modelXML.write(to: xml)
        let encoder = FakeGeometryEncoder(source: nil, replacement: Data())

        let result = await run(
            ["Editor", "-paste-xml", xml.path, "-output", fbx.path, "-o", saved.path],
            geometryEncoder: encoder)

        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertEqual(result.output.count, 2)
        let archive = try Data(contentsOf: saved)
        XCTAssertEqual(try Dust3DDocument(data: archive).editorContents().nodes.count, 1)
        let calls = await encoder.calls
        XCTAssertEqual(calls.map(\.format), [.fbxTextured])
        XCTAssertEqual(calls.map(\.archive), [archive])
    }

    private func run(_ arguments: [String], geometryEncoder: (any DocumentExportEncoding)? = nil) async
        -> (status: Int32?, output: [String], errors: [String])
    {
        var output: [String] = []
        var errors: [String] = []
        let status = await EditorHeadlessDS3SaveCommand.run(
            arguments: arguments, geometryEncoder: geometryEncoder, stdout: { output.append($0) },
            stderr: { errors.append($0) })
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

private actor FakeGeometryEncoder: DocumentExportEncoding {
    private enum Failure: Error { case obj }

    let source: URL?
    let replacement: Data
    private(set) var calls: [(archive: Data, format: DocumentExportFormat)] = []

    init(source: URL?, replacement: Data) {
        self.source = source
        self.replacement = replacement
    }

    func encode(archive: Data, format: DocumentExportFormat) async throws -> DocumentExportArtifact {
        calls.append((archive, format))
        if calls.count == 1, let source {
            try replacement.write(to: source, options: .atomic)
        }
        if format == .obj { throw Failure.obj }
        return DocumentExportArtifact(bytes: Data("inert FBX".utf8), warning: "")
    }
}
