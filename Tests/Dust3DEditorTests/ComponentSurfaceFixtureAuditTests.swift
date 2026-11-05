import CryptoKit
import Dust3DDocument
import Foundation
import XCTest

/// Data/XML-only review receipt. No fixture in this test is passed to a native entry point.
final class ComponentSurfaceFixtureAuditTests: XCTestCase {
    func testExportProposedBoundedFinishInputsForRootReviewWithoutNativeExecution() throws {
        let root = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["DUST3D_WRAPPING_AUDIT_DIR"] ?? NSTemporaryDirectory()
        ).appendingPathComponent("proposed-finish-inputs")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var rows: [[String: String]] = []
        for (name, data) in try SurfaceDetailFixtureVariants.inputs().sorted(by: { $0.key < $1.key }) {
            let document = try Dust3DDocument(data: data)
            let contents = try document.editorContents()
            XCTAssertEqual(contents.nodes.count, 1)
            XCTAssertTrue(contents.edges.isEmpty)
            XCTAssertEqual(contents.parts.count, 1)
            XCTAssertEqual(try document.components().count, 2)
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            try data.write(to: root.appendingPathComponent(name + ".ds3"))
            try document.modelXML.write(to: root.appendingPathComponent(name + ".xml"))
            rows.append(["name": name, "bytes": String(data.count), "sha256": hash])
        }
        let report = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
        try report.write(to: root.appendingPathComponent("input-audit.json"))
        print("Proposed finish input audit: \(root.path)")
    }
}
