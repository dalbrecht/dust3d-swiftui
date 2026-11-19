import Dust3DDocument
import Dust3DEditorModel
import Foundation
import XCTest

@MainActor
final class ComponentStitchingBatchTests: XCTestCase {
    private let lines: Set<String> = ["line-a", "line-b"]
    private let loops: Set<String> = ["loop-a", "loop-b"]

    private func source() throws -> Data {
        try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas><parts>
                <part id='a' target='StitchingLine'/><part id='b' target='StitchingLine'/>
                <part id='c' target='StitchingLoop'/><part id='d' target='StitchingLoop'/>
                </parts><components>
                <component id='line-a' frontClosed='True' targetSegments='future' opaque='keep'>
                  <component id='leaf-a' linkDataType='partId' linkData='a'/>
                </component>
                <component id='line-b' frontClosed='0' targetSegments='2'>
                  <component id='leaf-b' linkDataType='partId' linkData='b'/>
                </component>
                <component id='loop-a' backClosed='True' backCloseDepthRatio='future'>
                  <component id='leaf-c' linkDataType='partId' linkData='c'/>
                </component>
                <component id='loop-b' backClosed='1' backCloseSharpness='.1'>
                  <component id='leaf-d' linkDataType='partId' linkData='d'/>
                </component>
                <component id='empty' backClosed='1'/>
                </components></canvas>
                """.utf8)
        ).encoded()
    }

    func testLineBatchShowsMixedAndUnsupportedThenCommitsExactlyOnce() async throws {
        let original = try source()
        let session = EditorSession()
        _ = try await session.open(data: original)
        let before = try await session.selectComponents(lines)
        let target = ComponentStitchingBatchTarget(snapshot: before)
        XCTAssertTrue(target.supportsLine)
        XCTAssertFalse(target.supportsLoop)
        XCTAssertTrue(target.supportsBack)
        XCTAssertEqual(target.closure(.front), .mixed)
        XCTAssertEqual(target.targetSegments, .unsupported)

        let changed = try await session.editComponentStitchingBatch(.segments(24), target: target)
        XCTAssertEqual(changed.selectedComponentIDs, lines)
        let groupRows = changed.componentTree.rows.filter { lines.contains($0.id) }
        XCTAssertEqual(groupRows.map { $0.component.stitching.targetSegments }, [24, 24])
        XCTAssertEqual(groupRows.map { $0.component.childIDs }, [["leaf-a"], ["leaf-b"]])
        XCTAssertEqual(try attribute("opaque", on: "line-a", in: changed.document), "keep")
        XCTAssertEqual(try attribute("frontClosed", on: "line-a", in: changed.document), "True")
        let same = try await session.editComponentStitchingBatch(.segments(24), target: .init(snapshot: changed))
        XCTAssertEqual(same.documentRevision, changed.documentRevision)
        XCTAssertEqual(same.document.encoded(), changed.document.encoded())
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), original)
        XCTAssertFalse(undone.canUndo)
    }

    func testNumericDraftSourcesDistinguishEditsBehindTheSameAggregateStatus() async throws {
        let session = EditorSession()
        _ = try await session.open(data: source())
        let selected = try await session.selectComponents(lines)
        let before = ComponentStitchingBatchTarget(snapshot: selected)
        let changed = try await session.apply([.setComponentTargetSegments(id: "line-b", segments: 3)])
        let after = ComponentStitchingBatchTarget(snapshot: changed)
        XCTAssertEqual(before.targetSegments, .unsupported)
        XCTAssertEqual(after.targetSegments, .unsupported)
        XCTAssertEqual(before.segmentDraftValues, [nil, 2])
        XCTAssertEqual(after.segmentDraftValues, [nil, 3])

        let closureChanged = try await session.editComponentStitchingBatch(
            .closure(.front, true), target: after)
        XCTAssertEqual(
            ComponentStitchingBatchTarget(snapshot: closureChanged).segmentDraftValues,
            after.segmentDraftValues)
    }

    func testFrontAndSideClosuresCanBeAuthoredIndependently() async throws {
        let original = try source()
        let session = EditorSession()
        _ = try await session.open(data: original)
        let before = try await session.selectComponents(lines)
        let front = try await session.editComponentStitchingBatch(
            .closure(.front, true), target: .init(snapshot: before))
        let side = try await session.editComponentStitchingBatch(
            .closure(.side, true), target: .init(snapshot: front))
        let rows = side.componentTree.rows.filter { lines.contains($0.id) }
        XCTAssertEqual(rows.map { $0.component.stitching.closureValue(.front) }, [true, true])
        XCTAssertEqual(rows.map { $0.component.stitching.closureValue(.side) }, [true, true])
        XCTAssertEqual(rows.map { $0.component.stitching.closureValue(.back) }, [false, false])
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), front.document.encoded())
    }

    func testLoopDepthShapeAndMixedBackAreIndependent() async throws {
        let session = EditorSession()
        _ = try await session.open(data: source())
        let before = try await session.selectComponents(loops)
        let target = ComponentStitchingBatchTarget(snapshot: before)
        XCTAssertFalse(target.supportsLine)
        XCTAssertTrue(target.supportsLoop)
        XCTAssertEqual(target.closure(.back), .uniform(true))
        XCTAssertEqual(target.scalar(.depthRatio), .unsupported)
        let depth = try await session.editComponentStitchingBatch(.scalar(.depthRatio, 0.5), target: target)
        let sharp = try await session.editComponentStitchingBatch(
            .scalar(.sharpness, 0.75), target: .init(snapshot: depth))
        let loopRows = sharp.componentTree.rows.filter { loops.contains($0.id) }
        XCTAssertEqual(loopRows.map { $0.component.stitching.scalarValue(.depthRatio) }, [0.5, 0.5])
        XCTAssertEqual(loopRows.map { $0.component.stitching.scalarValue(.sharpness) }, [0.75, 0.75])
        let mixed = try await session.selectComponents(["line-a", "loop-a"])
        let mixedTarget = ComponentStitchingBatchTarget(snapshot: mixed)
        XCTAssertFalse(mixedTarget.supportsLine)
        XCTAssertFalse(mixedTarget.supportsLoop)
        XCTAssertTrue(mixedTarget.supportsBack)
        XCTAssertEqual(mixedTarget.closure(.back), .mixed)
        let closed = try await session.editComponentStitchingBatch(.closure(.back, true), target: mixedTarget)
        let rows = closed.componentTree.rows.filter { closed.selectedComponentIDs.contains($0.id) }
        XCTAssertEqual(rows.map { $0.component.stitching.closureValue(.back) }, [true, true])
        XCTAssertEqual(try attribute("backClosed", on: "loop-a", in: closed.document), "True")
    }

    func testLoopCapBatchRequiresEveryBackClosedAndPreservesDormantValues() async throws {
        let original = try Dust3DDocument(data: source()).applying(
            .setComponentStitchingClosure(id: "loop-b", property: .back, value: false))
        let session = EditorSession()
        _ = try await session.open(data: original.encoded())
        let before = try await session.selectComponents(loops)
        let target = ComponentStitchingBatchTarget(snapshot: before)
        XCTAssertEqual(target.closure(.back), .mixed)
        await rejects(.scalar(.sharpness, 0.75), target: target, in: session)
        let retained = try await session.animationSnapshot().editor
        XCTAssertEqual(retained.document.encoded(), before.document.encoded())
        XCTAssertFalse(retained.canUndo)

        let closed = try await session.editComponentStitchingBatch(.closure(.back, true), target: target)
        XCTAssertEqual(try attribute("backCloseSharpness", on: "loop-b", in: closed.document), ".1")
        let changed = try await session.editComponentStitchingBatch(
            .scalar(.sharpness, 0.75), target: .init(snapshot: closed))
        XCTAssertEqual(ComponentStitchingBatchTarget(snapshot: changed).scalar(.sharpness), .uniform(0.75))
        let undone = try await session.undo()
        XCTAssertEqual(undone.document.encoded(), closed.document.encoded())
    }

    func testInvalidHeterogeneousStaleAndFailedSourceRejectAtomically() async throws {
        let original = try source()
        let session = EditorSession()
        _ = try await session.open(data: original)
        let mixed = try await session.selectComponents(["line-a", "empty"])
        let mixedTarget = ComponentStitchingBatchTarget(snapshot: mixed)
        XCTAssertFalse(mixedTarget.supportsBack)
        await rejects(.closure(.back, true), target: mixedTarget, in: session)
        let linesBefore = try await session.selectComponents(lines)
        let stale = ComponentStitchingBatchTarget(snapshot: linesBefore)
        await rejects(.scalar(.depthRatio, 0.5), target: stale, in: session)
        await rejects(.segments(101), target: stale, in: session)
        _ = try await session.selectComponents(loops)
        let current = try await session.selectComponents(lines)
        await rejects(.closure(.front, true), target: stale, in: session)
        do {
            _ = try await session.open(data: Data("invalid archive".utf8))
            XCTFail("Invalid replacement opened")
        } catch {}
        await rejects(.closure(.front, true), target: .init(snapshot: current), in: session)
        let retained = try await session.animationSnapshot().editor
        XCTAssertEqual(retained.document.encoded(), original)
        XCTAssertEqual(retained.documentRevision, linesBefore.documentRevision)
        XCTAssertFalse(retained.canUndo)
    }

    private func attribute(_ name: String, on id: String, in document: Dust3DDocument) throws -> String? {
        let xml = try XMLDocument(data: document.modelXML)
        let row = try XCTUnwrap(try xml.nodes(forXPath: "//component[@id='\(id)']").first as? XMLElement)
        return row.attribute(forName: name)?.stringValue
    }

    private func rejects(
        _ edit: ComponentStitchingEdit, target: ComponentStitchingBatchTarget, in session: EditorSession
    ) async {
        do {
            _ = try await session.editComponentStitchingBatch(edit, target: target)
            XCTFail("Invalid or stale batch reached the document")
        } catch {}
    }
}
