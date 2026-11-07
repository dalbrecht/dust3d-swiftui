import XCTest

@testable import Dust3DEditor

final class EditorSaveAllCommandTests: XCTestCase {
    @MainActor
    func testSaveAllDelegatesOnceOnlyWhenDocumentsAreEdited() {
        let controller = SaveAllController()
        EditorSaveAllCommand.perform(in: controller)
        XCTAssertEqual(controller.saveRequests, 0)

        controller.hasEditedDocuments = true
        EditorSaveAllCommand.perform(in: controller)
        XCTAssertEqual(controller.saveRequests, 1)

        controller.hasEditedDocuments = false
        EditorSaveAllCommand.perform(in: controller)
        XCTAssertEqual(controller.saveRequests, 1)
    }
}

@MainActor
private final class SaveAllController: EditorSaveAllDocumentControlling {
    var hasEditedDocuments = false
    private(set) var saveRequests = 0

    func saveAllDocuments(_ sender: Any?) { saveRequests += 1 }
}
