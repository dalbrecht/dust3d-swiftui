import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

@testable import Dust3DEditor

final class ComponentStitchingOrderTests: XCTestCase {
    func testAuthoredOrderTracksDirectLineSiblingsAcrossReorderAndExactUndo() throws {
        let source = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><nodes/><edges/><parts>
                <part id='p1' target='StitchingLine'/>
                <part id='p2' target='StitchingLine' disabled='true'/>
                <part id='p3' target='StitchingLine' locked='true'/>
                <part id='p4' target='StitchingLine' visible='false'/>
                <part id='m' target='Model'/>
                <part id='l' target='StitchingLoop'/>
                </parts><components>
                <component id='rootLoop' linkDataType='partId' linkData='l'/>
                <component id='g'>
                    <component id='first' linkDataType='partId' linkData='p1'/>
                    <component id='model' linkDataType='partId' linkData='m'/>
                    <component id='nested'>
                        <component id='nestedFirst' linkDataType='partId' linkData='p3'/>
                        <component id='nestedSecond' linkDataType='partId' linkData='p4'/>
                    </component>
                    <component id='missing' linkDataType='partId' linkData='missingPart'/>
                    <component id='last' linkDataType='partId' linkData='p2'/>
                </component>
                </components></canvas>
                """.utf8))
        var state = try EditorState(document: source)
        let initial = ComponentStitchingOrder(snapshot: state.snapshot)
        XCTAssertTrue(initial.hasUngroupedStitching)
        XCTAssertFalse(initial.hasLineOrder(in: nil))
        XCTAssertTrue(initial.hasLineOrder(in: "g"))
        XCTAssertTrue(initial.hasLineOrder(in: "nested"))
        XCTAssertEqual(initial.ordinal(for: "first"), .init(position: 1, count: 2))
        XCTAssertEqual(initial.ordinal(for: "last"), .init(position: 2, count: 2))
        XCTAssertEqual(initial.ordinal(for: "nestedFirst"), .init(position: 1, count: 2))
        XCTAssertEqual(initial.ordinal(for: "nestedSecond"), .init(position: 2, count: 2))
        for id in ["rootLoop", "model", "missing", "g", "nested"] {
            XCTAssertNil(initial.ordinal(for: id))
        }

        try state.apply([.placeComponents(ids: ["last"], placement: .before("first"))])
        let reordered = ComponentStitchingOrder(snapshot: state.snapshot)
        XCTAssertEqual(reordered.ordinal(for: "last"), .init(position: 1, count: 2))
        XCTAssertEqual(reordered.ordinal(for: "first"), .init(position: 2, count: 2))
        XCTAssertEqual(reordered.ordinal(for: "nestedFirst"), initial.ordinal(for: "nestedFirst"))
        try state.undo()
        XCTAssertEqual(state.snapshot.document.encoded(), source.encoded())
        XCTAssertEqual(
            ComponentStitchingOrder(snapshot: state.snapshot).ordinal(for: "first"), initial.ordinal(for: "first"))
        XCTAssertFalse(state.snapshot.canUndo)
    }
}
