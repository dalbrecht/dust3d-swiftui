import Dust3DDocument
import Dust3DEditorModel
import XCTest

final class PartProfileOptionsTests: XCTestCase {
    private let owner = "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}"
    private let first = "{BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB}"
    private let second = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"

    private func document() throws -> Dust3DDocument {
        var document = try Dust3DDocument(data: Dust3DDocument.emptyArchive())
        for (index, id) in [owner, "legacy", first, second].enumerated() {
            document = try document.applying(
                .addNode(
                    id: "n\(index)", partID: id, componentID: "c\(index)",
                    position: .init(x: Double(index), y: 0, z: 0), radius: 0.1))
            document = try document.applying(.setPartName(id: id, name: "Duplicate Curve 曲線"))
        }
        return document
    }

    func testCandidatesExcludeLegacyIdentitiesAndSelfWithoutRewritingSource() throws {
        let document = try document()
        let parts = try document.editorContents().parts
        let before = document.encoded()
        XCTAssertEqual(parts.map(\.canBeCutFaceProfile), [true, false, true, true])
        XCTAssertEqual(
            PartProfileOptions.candidates(in: parts, excluding: owner, matching: "").map(\.id), [first, second])
        XCTAssertEqual(document.encoded(), before)
        XCTAssertEqual(
            try Dust3DDocument(data: before).editorContents().parts.map(\.id), [owner, "legacy", first, second])
    }

    func testSearchMatchesTitlesAndExactSourceIdentityCaseInsensitivelyInSourceOrder() throws {
        let parts = try document().editorContents().parts
        for query in ["CURVE", "曲線", "duplicate"] {
            XCTAssertEqual(
                PartProfileOptions.candidates(in: parts, excluding: owner, matching: query).map(\.id), [first, second])
        }
        XCTAssertEqual(
            PartProfileOptions.candidates(in: parts, excluding: owner, matching: first.lowercased()).map(\.id), [first])
        XCTAssertEqual(PartProfileOptions.candidates(in: parts, excluding: owner, matching: "missing").map(\.id), [])
        XCTAssertEqual(PartProfileOptions.candidates(in: parts, excluding: owner, matching: "legacy").map(\.id), [])
        XCTAssertTrue(PartProfileOptions.candidates(in: [], excluding: owner, matching: "").isEmpty)
    }
}
