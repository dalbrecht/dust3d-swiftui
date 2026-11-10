import XCTest

@testable import Dust3DEditor

@MainActor final class EditorPreviewFailureAnnouncementTests: XCTestCase {
    func testPreviewFailureAnnouncementUsesVisibleFailureAndKeyWindow() {
        let renderer = EditorPreviewFailureNotice(
            rendererError: "Renderer failed.", generationError: "Generation failed.",
            hasMesh: true)
        XCTAssertEqual(renderer?.announcement(isKeyWindow: true), "Preview unavailable. Renderer failed.")
        XCTAssertNil(renderer?.announcement(isKeyWindow: false))

        let retained = EditorPreviewFailureNotice(
            rendererError: nil, generationError: "Generation failed.",
            hasMesh: true)
        XCTAssertEqual(retained?.announcement(isKeyWindow: true), "Preview out of date: Generation failed.")

        let empty = EditorPreviewFailureNotice(
            rendererError: nil, generationError: "Generation failed.",
            hasMesh: false)
        XCTAssertEqual(empty?.announcement(isKeyWindow: true), "Preview unavailable. Generation failed.")

        XCTAssertNil(EditorPreviewFailureNotice(rendererError: nil, generationError: nil, hasMesh: true))
    }
}
