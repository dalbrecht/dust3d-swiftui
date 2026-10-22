import Foundation
import XCTest

@testable import Dust3DKit

final class SourceMeshBakeErrorTests: XCTestCase {
    func testDescribesEverySourceBoundaryFailureWithoutLosingItsTypedIdentity() {
        let cases: [(SourceMeshBakeError, String)] = [
            (.invalidLimits, "limits"), (.invalidInputImage, "image"), (.inputLimitExceeded, "decoded"),
            (.invalidNativeCounts, "counts"), (.copyLimitExceeded, "copied"), (.invalidCatalog, "catalog"),
            (.invalidTriangle, "triangle"), (.invalidPolicy, "policy"), (.invalidSamplingLod, "lod"),
        ]
        var messages = Set<String>()
        for (error, subject) in cases {
            XCTAssertTrue(error.localizedDescription.lowercased().contains(subject), error.localizedDescription)
            messages.insert(error.localizedDescription)
            let retained: any Error = error
            XCTAssertEqual(retained as? SourceMeshBakeError, error)
        }
        XCTAssertEqual(messages.count, cases.count)
    }
}
