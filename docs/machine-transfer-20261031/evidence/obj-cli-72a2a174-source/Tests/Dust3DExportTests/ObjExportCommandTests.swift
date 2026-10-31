import Foundation
import XCTest

@testable import Dust3DExport

final class ObjExportCommandTests: XCTestCase {
    func testParsesPositionalAndExplicitInputsAndQtOutputAliases() throws {
        let cwd = URL(fileURLWithPath: "/tmp/export-test", isDirectory: true)
        for arguments in [
            ["model.ds3", "-o", "mesh.obj"], ["-output", "mesh.obj", "model.ds3"],
            ["--input", "model.ds3", "--output", "mesh.obj"],
        ] {
            guard case .export(let input, let output) = try ObjExportCommand.parse(arguments, workingDirectory: cwd)
            else {
                return XCTFail("Expected export request")
            }
            XCTAssertEqual(input.path, "/tmp/export-test/model.ds3")
            XCTAssertEqual(output.path, "/tmp/export-test/mesh.obj")
        }
        guard
            case .export(let input, let output) = try ObjExportCommand.parse(
                ["--output", "/tmp/My Mesh.OBJ", "--", "-My Model.DS3"], workingDirectory: cwd)
        else {
            return XCTFail("Expected literal filename after separator")
        }
        XCTAssertEqual(input.lastPathComponent, "-My Model.DS3")
        XCTAssertEqual(output.lastPathComponent, "My Mesh.OBJ")
        guard case .help = try ObjExportCommand.parse(["--help"], workingDirectory: cwd) else {
            return XCTFail("Help must not export")
        }
    }

    func testRejectsInvalidRequestsBeforeAnyFileAccess() throws {
        let cwd = URL(fileURLWithPath: "/tmp", isDirectory: true)
        for arguments in [
            [], ["a.ds3"], ["--output"], ["--input"], ["--future"],
            ["a.ds3", "b.ds3", "-o", "a.obj"], ["a.ds3", "-o", "a.obj", "-o", "b.obj"],
            ["--input", "a.ds3", "b.ds3", "-o", "a.obj"], ["--help", "a.ds3"],
            ["a.ds3", "-o", "a.glb"], ["a.obj", "-o", "b.obj"],
            ["a.ds3", "-o", "\u{0}.obj"], ["a.ds3", "-o", String(repeating: "x", count: 4097) + ".obj"],
        ] {
            XCTAssertThrowsError(try ObjExportCommand.parse(arguments, workingDirectory: cwd)) {
                XCTAssertTrue($0 is ObjExportUsageError)
                XCTAssertFalse($0.localizedDescription.isEmpty)
            }
        }
    }
}
