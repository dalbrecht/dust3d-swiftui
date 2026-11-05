import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DEditor

final class WrappingBodyBindingPresentationTests: XCTestCase {
    func testCurrentValueDistinguishesOwnEligibleRetainedAndMissingWithoutChangingSource() throws {
        for (reference, title) in [
            ("", "Own Children"), ("body", "Body"), ("leaf", "Retained source target"),
            ("missing", "Unresolved source reference"), ("garment", "Retained source target"),
        ] {
            let document = try Dust3DDocument(
                snapshotXML: Data(
                    """
                    <canvas><nodes/><edges/><parts/><components><component id='body' name='Body'/><component id='garment' wrap='Cloth' wrapBindTo='\(reference)'><component id='leaf' linkDataType='future' linkData='opaque'/></component></components></canvas>
                    """.utf8))
            let before = document.encoded()
            let components = try document.components()
            let owner = try XCTUnwrap(components.first { $0.id == "garment" })
            let presentation = try ComponentWrapBindingPresentation(component: owner, components: components)
            XCTAssertEqual(presentation.currentTitle, title)
            XCTAssertEqual(presentation.currentReference, reference.isEmpty ? nil : reference)
            XCTAssertEqual(presentation.candidates.map(\.id), ["body"])
            XCTAssertEqual(document.encoded(), before)
        }
    }
    func testDuplicateNamedBodiesExposeExactDistinctCurrentReferencesToAccessibility() throws {
        var values: [String] = []
        for target in ["body-one", "body-two"] {
            let document = try Dust3DDocument(
                snapshotXML: Data(
                    """
                    <canvas><nodes/><edges/><parts/><components><component id='body-one' name='Body'/><component id='body-two' name='Body'/><component id='garment' wrap='Cloth' wrapBindTo='\(target)'/></components></canvas>
                    """.utf8))
            let components = try document.components()
            let presentation = try ComponentWrapBindingPresentation(
                component: XCTUnwrap(components.first { $0.id == "garment" }), components: components)
            XCTAssertEqual(presentation.currentTitle, "Body")
            XCTAssertEqual(presentation.accessibilityValue, "Body: \(target)")
            values.append(presentation.accessibilityValue)
        }
        XCTAssertNotEqual(values[0], values[1])
    }

    func testUnnamedBodySpeaksItsExactIdentifierOnlyOnce() throws {
        let document = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes/><edges/><parts/><components><component id='body'/><component id='garment' wrap='Cloth' wrapBindTo='body'/></components></canvas>
                """.utf8))
        let components = try document.components()
        let presentation = try ComponentWrapBindingPresentation(
            component: XCTUnwrap(components.first { $0.id == "garment" }), components: components)
        XCTAssertEqual(presentation.currentTitle, "body")
        XCTAssertEqual(presentation.accessibilityValue, "body")
    }

}
