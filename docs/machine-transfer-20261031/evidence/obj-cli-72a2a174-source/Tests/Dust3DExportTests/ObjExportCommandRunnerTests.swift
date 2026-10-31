import Dust3DKit
import Foundation
import XCTest

@testable import Dust3DExport
@testable import Dust3DKit

final class ObjExportCommandRunnerTests: XCTestCase {
    func testPreservesOriginalCauseAndStageAtEveryBoundary() async throws {
        let url = URL(fileURLWithPath: "/tmp/unused.obj")
        let cause = NSError(domain: "org.dust3d.test-original", code: 42)
        let generated = output()
        for stage in [ObjExportCommandStage.reading, .generating, .writing] {
            let runner = ObjExportCommandRunner(
                read: { _ in
                    if stage == .reading { throw cause }
                    return Data([1])
                },
                exporter: Exporter(output: generated, failure: stage == .generating ? cause : nil),
                writer: Writer(failure: stage == .writing ? cause : nil))
            do {
                _ = try await runner.run(input: url, output: url) { _ in }
                XCTFail("Boundary failure must propagate")
            } catch let failure as ObjExportCommandFailure {
                XCTAssertEqual(failure.stage, stage)
                XCTAssertEqual((failure.cause as NSError).domain, cause.domain)
                XCTAssertEqual((failure.cause as NSError).code, cause.code)
            }
        }
    }

    func testSuccessfulCommitWinsLateCancellationAndRetainsWarnings() async throws {
        let generated = output()
        let destination = URL(fileURLWithPath: "/tmp/unused.obj")
        let task = Task {
            try await ObjExportCommandRunner(
                read: { _ in Data([1]) }, exporter: Exporter(output: generated), writer: Writer(cancelAfterCommit: true)
            ).run(input: destination, output: destination) { _ in }
        }
        let receipt = try await task.value
        XCTAssertEqual(receipt.destination, destination.path)
        XCTAssertEqual(receipt.byteCount, generated.data.count)
        XCTAssertEqual(receipt.vertexCount, generated.vertexCount)
        XCTAssertEqual(receipt.sourceWarnings, generated.warning)
    }

    func testPrecancelledRequestNeverReadsSource() async throws {
        let generated = output()
        let destination = URL(fileURLWithPath: "/tmp/unused.obj")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ObjExportCommandRunner(
                read: { _ in throw NSError(domain: "unexpected-read", code: 1) },
                exporter: Exporter(output: generated), writer: Writer()
            ).run(input: destination, output: destination) { _ in }
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled request accepted")
        } catch is CancellationError {}
    }

    private func output() -> ObjExport {
        ObjExport(
            data: Data([1]), vertexCount: 3, triangleCount: 1, warning: "original warning",
            nativePayloadBytes: 1, copiedPayloadBytes: 1)
    }
    private struct Exporter: ObjExporting {
        let output: ObjExport
        var failure: NSError? = nil
        func encode(data: Data, options: ObjExportOptions) async throws -> ObjExport {
            if let failure { throw failure }
            return output
        }
    }
    private struct Writer: ObjExportFileWriting {
        var failure: NSError? = nil
        var cancelAfterCommit = false
        func write(output: ObjExport, to destination: URL) async throws -> ObjExportWriteReceipt {
            if let failure { throw failure }
            if cancelAfterCommit { withUnsafeCurrentTask { $0?.cancel() } }
            return ObjExportWriteReceipt(destination: destination, byteCount: output.data.count)
        }
    }
}
