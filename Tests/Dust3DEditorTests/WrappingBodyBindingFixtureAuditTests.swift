import CryptoKit
import Dust3DDocument
import Foundation
import XCTest

/// Data construction/export only. No preview, material service or native geometry entry point is called.
final class WrappingBodyBindingFixtureAuditTests: XCTestCase {
    func testBoundedFamilyHasGloballyDistinctIdentitiesAndExportsForReviewWithoutNativeExecution() throws {
        let family = try BodyBindingFixtureFamily.inputs()
        XCTAssertEqual(Set(family.keys), ["own", "body", "own-after", "empty"])
        var records: [[String: Any]] = []
        let directory = ProcessInfo.processInfo.environment["DUST3D_BODY_BINDING_AUDIT_DIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        if let directory { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        for name in family.keys.sorted() {
            let data = try XCTUnwrap(family[name])
            let document = try Dust3DDocument(data: data)
            let contents = try document.editorContents()
            let components = try document.components()
            XCTAssertEqual(contents.nodes.count, 4)
            XCTAssertEqual(contents.edges.count, 2)
            XCTAssertEqual(contents.parts.count, 2)
            XCTAssertEqual(components.count, 5)
            let ids =
                contents.nodes.map(\.id) + contents.edges.map(\.id) + contents.parts.map(\.id) + components.map(\.id)
            XCTAssertEqual(Set(ids).count, 13)
            XCTAssertEqual(document.asset(named: "opaque.bin"), Data([0, 255, 10, 128]))
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            records.append(["name": name, "bytes": data.count, "sha256": hash])
            if let directory { try data.write(to: directory.appendingPathComponent(name + ".ds3")) }
        }
        if let directory {
            let manifest = try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
            try manifest.write(to: directory.appendingPathComponent("inputs.json"))
        }
    }
}
