import Foundation
import XCTest

@testable import Dust3DKit

@MainActor
final class MeshFileServiceTests: XCTestCase {
    func testLoadsExistingDocumentOffTheUIActor() async throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Capsule", withExtension: "ds3", subdirectory: "Fixtures"))
        let mesh = try await MeshFileService().load(url: url)
        XCTAssertGreaterThan(mesh.triangleCount, 0)
    }

    func testMissingFilePreservesFileSystemError() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ds3")
        do {
            _ = try await MeshFileService().load(url: url)
            XCTFail("A missing file must fail.")
        } catch {
            XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
        }
    }

    func testOversizedFileIsRejectedBeforeReadingItsContents() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ds3")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data()))
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try FileHandle(forWritingTo: url)
        try file.truncate(atOffset: UInt64(MeshLoader.maximumFileSize + 1))
        try file.close()
        do {
            _ = try await MeshFileService().load(url: url)
            XCTFail("An oversized file must fail.")
        } catch let error as MeshLoadingError {
            XCTAssertEqual(error.status, 4)
        }
    }

    func testCancelledLoadDoesNotGenerateAMesh() async throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Capsule", withExtension: "ds3", subdirectory: "Fixtures"))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await MeshFileService().load(url: url)
        }
        do {
            _ = try await task.value
            XCTFail("A cancelled load must fail.")
        } catch is CancellationError {
            // Expected: cancellation is checked before entering native generation.
        }
    }

    func testEmptyFilePreservesTheNativeDiagnostic() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ds3")
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try await MeshFileService().load(url: url)
            XCTFail("An empty file must fail.")
        } catch let error as MeshLoadingError {
            XCTAssertEqual(error.status, 1)
            XCTAssertTrue(error.message.contains("nonempty"))
        }
    }
}
