import Foundation
import XCTest

@testable import Dust3DEditor

final class EditorDocumentDropTests: XCTestCase {
    func testOneLocalDocumentKeepsOriginalURL() throws {
        let original = URL(fileURLWithPath: "/tmp/Dust3D Examples/../My Model.DS3")
        let admitted = try XCTUnwrap(EditorDocumentDrop(urls: [original]))
        XCTAssertEqual(admitted.url.absoluteString, original.absoluteString)
    }

    func testEmptyMultipleMixedRemoteAndMalformedDropsAreRejected() throws {
        let model = URL(fileURLWithPath: "/tmp/model.ds3")
        let image = URL(fileURLWithPath: "/tmp/front.png")
        let directory = URL(fileURLWithPath: "/tmp/Directory.ds3", isDirectory: true)
        let remote = try XCTUnwrap(URL(string: "https://example.com/model.ds3"))
        let remoteFile = try XCTUnwrap(URL(string: "file://example.com/tmp/model.ds3"))
        let query = try XCTUnwrap(URL(string: "file:///tmp/model.ds3?other=1"))
        for urls in [
            [], [model, model], [model, image], [image], [directory], [remote], [remoteFile], [query],
            [URL(fileURLWithPath: "/tmp/" + String(repeating: "x", count: 4096) + ".ds3")],
            [URL(fileURLWithPath: "/tmp/invalid\0name.ds3")],
        ] {
            XCTAssertNil(EditorDocumentDrop(urls: urls), "Unexpectedly admitted \(urls)")
        }
    }

    @MainActor
    func testAdmittedDropInvokesNativeRouteOnceAndPreservesOriginalError() async throws {
        enum OpenFailure: Error, Equatable { case denied }
        let url = URL(fileURLWithPath: "/tmp/model.ds3")
        let drop = try XCTUnwrap(EditorDocumentDrop(urls: [url]))
        var opened: [URL] = []
        var errors: [OpenFailure] = []
        await drop.open(
            using: {
                opened.append($0)
                throw OpenFailure.denied
            },
            reportError: { if let error = $0 as? OpenFailure { errors.append(error) } })
        XCTAssertEqual(opened, [url])
        XCTAssertEqual(errors, [.denied])
        await drop.open(
            using: { opened.append($0) },
            reportError: { XCTFail("Unexpected error: \($0)") })
        XCTAssertEqual(opened, [url, url])
        XCTAssertEqual(errors, [.denied])
    }
}
