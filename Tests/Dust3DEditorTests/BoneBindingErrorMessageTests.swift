import Dust3DDocument
import XCTest

@testable import Dust3DEditor

final class BoneBindingErrorMessageTests: XCTestCase {
    @MainActor func testInvalidBoneNameExplainsIdentityAndInputLimits() {
        XCTAssertEqual(
            EditorStore.message(DocumentError.invalidBoneName),
            "Use an exact bone name of at most 1024 UTF-8 bytes without controls or newlines.")
    }
}
