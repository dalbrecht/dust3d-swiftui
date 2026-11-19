import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DEditor

@MainActor
final class AnimationWavExportTests: XCTestCase {
    func testCancellationAndRetiredSelectionPreserveDestination() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let destination = folder.appendingPathComponent("existing.wav")
        let previous = Data([0])
        try previous.write(to: destination)
        var current = true
        let cancelled = try await AnimationWavExport.save(
            sourceURL: nil, choose: { nil },
            encode: {
                XCTFail("Cancelled panel encoded")
                return Data()
            },
            isCurrent: { current })
        XCTAssertFalse(cancelled)
        let retiredInPanel = try await AnimationWavExport.save(
            sourceURL: nil,
            choose: {
                current = false
                return destination
            },
            encode: {
                XCTFail("Retired panel result encoded")
                return Data()
            }, isCurrent: { current })
        XCTAssertFalse(retiredInPanel)
        current = true
        let replaced = try await AnimationWavExport.save(
            sourceURL: nil, choose: { destination },
            encode: {
                current = false
                return Data([1])
            },
            isCurrent: { current })
        XCTAssertFalse(replaced)
        XCTAssertEqual(try Data(contentsOf: destination), previous)
    }

    func testCurrentCaptureReplacesDestinationAndRejectsSourceAlias() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("document.ds3")
        let destination = folder.appendingPathComponent("existing.wav")
        try Data([0]).write(to: source)
        try FileManager.default.linkItem(at: source, to: destination)
        do {
            _ = try await AnimationWavExport.save(
                sourceURL: source, choose: { destination }, encode: { Data([1]) }, isCurrent: { true })
            XCTFail("Allowed an alias of the source document")
        } catch let failure as DocumentExportError {
            XCTAssertEqual(failure, .sourceAlias)
        }
        XCTAssertEqual(try Data(contentsOf: source), Data([0]))
        try FileManager.default.removeItem(at: destination)
        try Data([0]).write(to: destination)
        let written = try await AnimationWavExport.save(
            sourceURL: source, choose: { destination }, encode: { Data([1]) }, isCurrent: { true })
        XCTAssertTrue(written)
        XCTAssertEqual(try Data(contentsOf: destination), Data([1]))
        XCTAssertEqual(try Data(contentsOf: source), Data([0]))
    }
}
