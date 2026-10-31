import Darwin
import Foundation
import XCTest

@MainActor
final class ObjExportProcessTests: XCTestCase {
    func testExportsRealArchiveWithCleanJSONReceiptAndPreservesInput() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Dust3DKitTests/Fixtures/Capsule.ds3")
        let original = try Data(contentsOf: fixture)
        let input = directory.appendingPathComponent("My Model.ds3")
        let output = directory.appendingPathComponent("My Mesh.obj")
        try original.write(to: input)
        try Data("old destination".utf8).write(to: output)
        let result = try await run([input.path, "-output", output.path])
        XCTAssertEqual(result.code, 0, String(decoding: result.error, as: UTF8.self))
        let receipt = try XCTUnwrap(JSONSerialization.jsonObject(with: result.output) as? [String: Any])
        XCTAssertEqual(receipt["destination"] as? String, output.path)
        XCTAssertEqual(receipt["triangleCount"] as? Int, 80)
        let mesh = try String(contentsOf: output, encoding: .utf8)
        XCTAssertEqual(mesh.split(separator: "\n").filter { $0.hasPrefix("f ") }.count, 80)
        XCTAssertEqual(receipt["byteCount"] as? Int, mesh.utf8.count)
        XCTAssertEqual(try Data(contentsOf: input), original)
        XCTAssertTrue(String(decoding: result.error, as: UTF8.self).contains("\"stage\":\"writing\""))
    }

    func testUsageReadAndGenerationFailuresHaveNonzeroStatusAndPreserveDestination() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("bad.ds3")
        let output = directory.appendingPathComponent("keep.obj")
        let sentinel = Data("keep these bytes".utf8)
        try sentinel.write(to: output)
        for (arguments, expectedCode, stage) in [
            (["--unknown"], Int32(2), "arguments"),
            ([input.path, "-o", output.path], Int32(1), "reading"),
        ] {
            let result = try await run(arguments)
            XCTAssertEqual(result.code, expectedCode)
            XCTAssertTrue(result.output.isEmpty)
            XCTAssertTrue(String(decoding: result.error, as: UTF8.self).contains("\"stage\":\"\(stage)\""))
        }
        try Data("not a Dust3D archive".utf8).write(to: input)
        let invalid = try await run([input.path, "-o", output.path])
        XCTAssertEqual(invalid.code, 1)
        XCTAssertTrue(invalid.output.isEmpty)
        XCTAssertTrue(String(decoding: invalid.error, as: UTF8.self).contains("\"stage\":\"generating\""))
        XCTAssertEqual(try Data(contentsOf: output), sentinel)
        let help = try await run(["--help"])
        XCTAssertEqual(help.code, 0)
        XCTAssertTrue(String(decoding: help.output, as: UTF8.self).contains("Dust3DExport"))
        XCTAssertTrue(help.error.isEmpty)
    }

    func testSIGINTCancelsCoordinatedWriteWithoutReplacingDestination() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Dust3DKitTests/Fixtures/Capsule.ds3")
        let output = directory.appendingPathComponent("held.obj")
        let sentinel = Data("held original".utf8)
        try sentinel.write(to: output)
        let release = DispatchSemaphore(value: 0)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            DispatchQueue(label: "org.dust3d.cli-test-reader").async {
                let coordinator = NSFileCoordinator(filePresenter: nil)
                var error: NSError?
                var admitted = false
                coordinator.coordinate(readingItemAt: output, options: .withoutChanges, error: &error) { _ in
                    admitted = true
                    continuation.resume()
                    _ = release.wait(timeout: .now() + 8)
                }
                if !admitted { continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown)) }
            }
        }
        defer { release.signal() }
        let result = try await run([input.path, "-o", output.path], interruptOnWriting: true)
        XCTAssertEqual(result.code, 130, String(decoding: result.error, as: UTF8.self))
        XCTAssertTrue(result.output.isEmpty)
        XCTAssertTrue(String(decoding: result.error, as: UTF8.self).contains("Export cancelled before commit."))
        XCTAssertEqual(try Data(contentsOf: output), sentinel)
    }

    private struct Result: Sendable {
        let code: Int32
        let output: Data
        let error: Data
    }
    private func run(_ arguments: [String], interruptOnWriting: Bool = false) async throws -> Result {
        let root = try XCTUnwrap(ProcessInfo.processInfo.environment["DUST3D_BUILD_ROOT"])
        let process = Process()
        process.executableURL = URL(fileURLWithPath: root).appendingPathComponent("build/debug/Dust3DExport")
        process.arguments = arguments
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        let outputTask = Task.detached { try output.fileHandleForReading.readToEnd() ?? Data() }
        let errorTask = Task.detached {
            var bytes = Data()
            var interrupted = false
            while true {
                let chunk = error.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                bytes.append(chunk)
                if interruptOnWriting && !interrupted
                    && String(decoding: bytes, as: UTF8.self).contains("\"stage\":\"writing\"")
                {
                    interrupted = true
                    Darwin.kill(process.processIdentifier, SIGINT)
                }
            }
            return bytes
        }
        await Task.detached { process.waitUntilExit() }.value
        return try await Result(code: process.terminationStatus, output: outputTask.value, error: errorTask.value)
    }
}
