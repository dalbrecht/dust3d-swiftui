import Dust3DDocument
import Foundation
import XCTest

/// Data-only oracle check: no preview, baking, catalog, foreign API or native fixture execution.
final class ComponentSubtreeDeletionArchiveTests: XCTestCase {
    func testTwoDocumentDeletesExactlyMatchIndependentlyAuthoredSerializationPasses() throws {
        let source = try XCTUnwrap(
            Data(
                base64Encoded:
                    "RFVTVDNEIDEuMCB4bWwgMDAwMDAwMDA4NQ0KPGRzMz48bW9kZWwgbmFtZT0nbW9kZWwueG1sJyBvZmZzZXQ9JzAnIHNpemU9Jzk1NCcvPjwvZHMzPjxjYW52YXMgb3JpZ2luWD0nLjUnIG9yaWdpblk9Jy41JyBvcmlnaW5aPScuNSc+PG5vZGVzPjxub2RlIGlkPSd7MDAwMDEwMDEtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAxMDAxfScgcGFydElkPSd7MDAwMDAxMDEtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMTAxfScgeD0nLjI1JyB5PScuNScgej0nLjUnIHJhZGl1cz0nLjE1Jy8+PG5vZGUgaWQ9J3swMDAwMTAwMi0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDEwMDJ9JyBwYXJ0SWQ9J3swMDAwMDEwMi0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAxMDJ9JyB4PScuNzUnIHk9Jy41JyB6PScuNScgcmFkaXVzPScuMTUnLz48L25vZGVzPjxlZGdlcy8+PHBhcnRzPjxwYXJ0IGlkPSd7MDAwMDAxMDEtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMTAxfScvPjxwYXJ0IGlkPSd7MDAwMDAxMDItMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMTAyfScvPjwvcGFydHM+PGNvbXBvbmVudHM+PGNvbXBvbmVudCBpZD0nezAwMDAwMzAxLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDMwMX0nIG5hbWU9J0xlZnQnIGNvbWJpbmVNb2RlPSdVbmNvbWJpbmVkJz48Y29tcG9uZW50IGlkPSd7MDAwMDAyMDEtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMjAxfScgbGlua0RhdGFUeXBlPSdwYXJ0SWQnIGxpbmtEYXRhPSd7MDAwMDAxMDEtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMTAxfScvPjwvY29tcG9uZW50Pjxjb21wb25lbnQgaWQ9J3swMDAwMDMwMi0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAzMDJ9JyBuYW1lPSdSaWdodCcgY29tYmluZU1vZGU9J1VuY29tYmluZWQnPjxjb21wb25lbnQgaWQ9J3swMDAwMDIwMi0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAyMDJ9JyBsaW5rRGF0YVR5cGU9J3BhcnRJZCcgbGlua0RhdGE9J3swMDAwMDEwMi0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAxMDJ9Jy8+PC9jb21wb25lbnQ+PC9jb21wb25lbnRzPjwvY2FudmFzPg=="
            ))
        let remainder = try XCTUnwrap(
            Data(
                base64Encoded:
                    "0z1EVVNUM0QgMS4wIHhtbCAwMDAwMDAwMTA4DQo8P3htbCB2ZXJzaW9uPSIxLjAiPz48ZHMzPjxtb2RlbCBuYW1lPSdtb2RlbC54bWwnIG9mZnNldD0nMCcgc2l6ZT0nNTU4Jy8+PC9kczM+PD94bWwgdmVyc2lvbj0iMS4wIj8+PGNhbnZhcyBvcmlnaW5YPScuNScgb3JpZ2luWT0nLjUnIG9yaWdpblo9Jy41Jz48bm9kZXM+PG5vZGUgaWQ9J3swMDAwMTAwMi0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDEwMDJ9JyBwYXJ0SWQ9J3swMDAwMDEwMi0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAxMDJ9JyB4PScuNzUnIHk9Jy41JyB6PScuNScgcmFkaXVzPScuMTUnLz48L25vZGVzPjxlZGdlcy8+PHBhcnRzPjxwYXJ0IGlkPSd7MDAwMDAxMDItMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMTAyfScvPjwvcGFydHM+PGNvbXBvbmVudHM+PGNvbXBvbmVudCBpZD0nezAwMDAwMzAyLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDMwMn0nIG5hbWU9J1JpZ2h0JyBjb21iaW5lTW9kZT0nVW5jb21iaW5lZCc+PGNvbXBvbmVudCBpZD0nezAwMDAwMjAyLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDIwMn0nIGxpbmtEYXRhVHlwZT0ncGFydElkJyBsaW5rRGF0YT0nezAwMDAwMTAyLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDEwMn0nLz48L2NvbXBvbmVudD48L2NvbXBvbmVudHM+PC9jYW52YXM+"
            ))
        let empty = try XCTUnwrap(
            Data(
                base64Encoded:
                    "0z1EVVNUM0QgMS4wIHhtbCAwMDAwMDAwMTI1DQo8P3htbCB2ZXJzaW9uPSIxLjAiIHN0YW5kYWxvbmU9InllcyI/PjxkczM+PG1vZGVsIG5hbWU9J21vZGVsLnhtbCcgb2Zmc2V0PScwJyBzaXplPScxMzEnLz48L2RzMz48P3htbCB2ZXJzaW9uPSIxLjAiIHN0YW5kYWxvbmU9InllcyI/PjxjYW52YXMgb3JpZ2luWD0nLjUnIG9yaWdpblk9Jy41JyBvcmlnaW5aPScuNSc+PG5vZGVzLz48ZWRnZXMvPjxwYXJ0cy8+PGNvbXBvbmVudHMvPjwvY2FudmFzPg=="
            ))
        let original = try Dust3DDocument(data: source)
        let first = try original.applying(.removeComponentSubtrees(["{00000301-0000-4000-8000-000000000301}"]))
        XCTAssertEqual(first.encoded(), remainder)
        let second = try first.applying(.removeComponentSubtrees(["{00000302-0000-4000-8000-000000000302}"]))
        XCTAssertEqual(second.encoded(), empty)
        XCTAssertTrue(try second.editorContents().nodes.isEmpty)
        XCTAssertTrue(try second.editorContents().edges.isEmpty)
        XCTAssertTrue(try second.editorContents().parts.isEmpty)
        XCTAssertTrue(try second.components().isEmpty)
    }
}
