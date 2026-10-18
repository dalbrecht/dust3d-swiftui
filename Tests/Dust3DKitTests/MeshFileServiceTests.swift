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

extension MeshFileServiceTests {
    func testIndexedFileLoadingCopiesIndicesAndPreservesFileErrors() async throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Capsule", withExtension: "ds3", subdirectory: "Fixtures"))
        let mesh = try await MeshFileService().loadIndexed(url: url)
        XCTAssertGreaterThan(mesh.triangleCount, 0)
        XCTAssertLessThan(mesh.vertices.count, mesh.indices.count)
        XCTAssertTrue(mesh.indices.allSatisfy { Int($0) < mesh.vertices.count })
        do {
            _ = try await MeshFileService().loadIndexed(url: url.appendingPathComponent("missing"))
            XCTFail("A missing indexed source must fail")
        } catch {
            XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
        }
    }
}

extension MeshFileServiceTests {
    func testShouldReturnTheExactArchiveSnapshotUsedForIndexedGeometry() async throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Capsule", withExtension: "ds3", subdirectory: "Fixtures"))
        let loaded = try await MeshFileService().loadIndexedSnapshot(url: url)
        XCTAssertEqual(loaded.data, try Data(contentsOf: url))
        let independentlyLoaded = try MeshLoader.loadIndexed(data: loaded.data)
        XCTAssertEqual(loaded.mesh.indices, independentlyLoaded.indices)
        XCTAssertEqual(loaded.mesh.vertices.map(\.position), independentlyLoaded.vertices.map(\.position))
    }
}

extension MeshFileServiceTests {
    func testShouldReadExactBoundedArchiveAndRejectInvalidPreviewReadBudgets() async throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Capsule", withExtension: "ds3", subdirectory: "Fixtures"))
        let bytes = try Data(contentsOf: url)
        let loaded = try await MeshFileService().readArchive(url: url, maximumBytes: bytes.count)
        XCTAssertEqual(loaded, bytes)
        for budget in [0, bytes.count - 1, MeshLoader.maximumFileSize + 1] {
            do {
                _ = try await MeshFileService().readArchive(url: url, maximumBytes: budget)
                XCTFail("Invalid or exceeded preview budget must fail")
            } catch let error as MeshLoadingError { XCTAssertEqual(error.status, 4) }
        }
    }
}
