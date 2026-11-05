import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DEditorModel

final class GraphReferenceColorPlanTests: XCTestCase {
    private func state(
        partState: String = "", extraEdges: String = "", extraComponents: String = "", omitPComponent: Bool = false
    ) throws -> EditorState {
        let xml =
            "<canvas><nodes><node id='a' partId='p' x='.125' y='.25' z='1.625' radius='.01'/><node id='b' partId='p' x='.625' y='.25' z='1.125' radius='.01'/><node id='c' partId='p' x='1.125' y='.25' z='.625' radius='.01'/><node id='d' partId='q' x='1.625' y='.25' z='.125' radius='.01'/><node id='outside' partId='q' x='3' y='2' z='3' radius='.01'/></nodes><edges><edge id='ab' partId='q' from='a' to='b'/>\(extraEdges)</edges><parts><part id='p' \(partState)/><part id='q'/></parts><components><component id='cp' linkDataType='partId' linkData='p' color='#123456' colorImageId='retained'/><component id='cq' linkDataType='partId' linkData='q'/></components></canvas>"
        let pComponent =
            "<component id='cp' linkDataType='partId' linkData='p' color='#123456' colorImageId='retained'/>"
        let configured = xml.replacingOccurrences(of: "</components>", with: "\(extraComponents)</components>")
        return try EditorState(
            document: Dust3DDocument(
                snapshotXML: Data(
                    (omitPComponent ? configured.replacingOccurrences(of: pComponent, with: "") : configured).utf8)))
    }

    private func raster() throws -> ReferenceColorRaster {
        try ReferenceColorRaster(
            width: 4, height: 2, rowStride: 16,
            pixels: Data([
                1, 10, 20, 0, 1, 10, 20, 255, 10, 30, 50, 128, 200, 150, 100, 255,
                7, 8, 9, 255, 7, 8, 9, 255, 7, 8, 9, 255, 7, 8, 9, 255,
            ]))
    }

    private func layout(_ snapshot: EditorSnapshot, plane: EditingPlane = .front) throws -> ReferenceColorSamplingLayout
    {
        try ReferenceColorSamplingLayout(
            referenceSize: .init(width: 4, height: 2),
            projection: .init(
                bounds: .init(nodes: snapshot.nodes, referenceImageAspectRatio: 2), plane: plane, width: 700,
                height: 500))
    }

    func testDistinctColorsIgnoreFrequenciesAndAlphaWithTruncatedOpaqueMeans() throws {
        var state = try state()
        try state.selectGraph(nodes: ["a", "b", "c"], edges: [])
        let plan = try GraphReferenceColorPlan.autoColor(
            snapshot: state.snapshot, raster: raster(), layout: layout(state.snapshot))
        XCTAssertEqual(plan.updates, [.init(componentID: "cp", color: .init(red: 5, green: 20, blue: 35))])
        XCTAssertEqual(plan.skippedReadOnlyObjects, 0)
        XCTAssertEqual(plan.skippedOutsideObjects, 0)
    }

    func testExplicitEdgeSamplesMidpointUnderActualEdgeOwnerWithoutAddingEndpoints() throws {
        var state = try state()
        try state.selectGraph(nodes: ["c"], edges: ["ab"])
        let plan = try GraphReferenceColorPlan.autoColor(
            snapshot: state.snapshot, raster: raster(), layout: layout(state.snapshot))
        XCTAssertEqual(
            plan.updates,
            [
                .init(componentID: "cp", color: .init(red: 10, green: 30, blue: 50)),
                .init(componentID: "cq", color: .init(red: 1, green: 10, blue: 20)),
            ])
        let side = try GraphReferenceColorPlan.autoColor(
            snapshot: state.snapshot, raster: raster(), layout: layout(state.snapshot, plane: .side))
        XCTAssertEqual(side.updates.first?.color, .init(red: 1, green: 10, blue: 20))
        XCTAssertEqual(side.updates.last?.color, .init(red: 10, green: 30, blue: 50))
    }

    func testClearUsesExplicitNodesOnlyAndCommandsPreserveOtherMetadataAndHistory() throws {
        var state = try state()
        try state.selectGraph(nodes: ["a", "b"], edges: ["ab"])
        let original = state.snapshot.document.encoded()
        let plan = try GraphReferenceColorPlan.clear(snapshot: state.snapshot)
        XCTAssertEqual(plan.updates, [.init(componentID: "cp", color: nil)])
        try state.apply(plan.commands)
        XCTAssertEqual(state.snapshot.componentTree.rows.first?.component.color, .unset)
        XCTAssertEqual(state.snapshot.componentTree.rows.first?.component.colorImage, .unsupported("retained"))
        let changed = state.snapshot.document.encoded()
        try state.undo()
        XCTAssertEqual(state.snapshot.document.encoded(), original)
        try state.redo()
        XCTAssertEqual(state.snapshot.document.encoded(), changed)
        XCTAssertEqual(try Dust3DDocument(data: changed).editorContents().nodes, state.snapshot.nodes)
        let revision = state.snapshot.documentRevision
        try state.apply(plan.commands)
        XCTAssertEqual(state.snapshot.documentRevision, revision)
        try state.undo()
        XCTAssertEqual(state.snapshot.document.encoded(), original)
    }

    func testReadOnlyObjectsAndOutsideSamplesAreSkippedWithoutChangingSelectionOrDocument() throws {
        for partState in ["locked='true'", "visible='false'", "disabled='true'"] {
            var state = try state(partState: partState)
            try state.selectGraph(nodes: ["a", "outside"], edges: ["ab"])
            let before = state.snapshot
            let plan = try GraphReferenceColorPlan.autoColor(snapshot: before, raster: raster(), layout: layout(before))
            XCTAssertEqual(plan.skippedReadOnlyObjects, 1)
            XCTAssertEqual(plan.skippedOutsideObjects, 1)
            XCTAssertEqual(plan.updates.map(\.componentID), ["cq"])
            // Blank does not sample the image, so the editable outside node still contributes its owner.
            XCTAssertEqual(
                try GraphReferenceColorPlan.clear(snapshot: before).updates, [.init(componentID: "cq", color: nil)])
            XCTAssertEqual(state.snapshot.document.encoded(), before.document.encoded())
            XCTAssertEqual(state.snapshot.selectedIDs, before.selectedIDs)
        }
    }

    func testNodeAdmissionAndUnresolvableEdgeOwnerAreExplicit() throws {
        var state = try state(extraEdges: "<edge id='unowned' from='a' to='b'/>")
        try state.selectGraph(nodes: [], edges: ["ab"])
        XCTAssertFalse(GraphReferenceColorPlan.canColorize(snapshot: state.snapshot))
        // The pure Qt method can plan edges; only the user-facing action's admission requires a node.
        XCTAssertEqual(
            try GraphReferenceColorPlan.autoColor(
                snapshot: state.snapshot, raster: raster(), layout: layout(state.snapshot)
            ).updates, [.init(componentID: "cq", color: .init(red: 1, green: 10, blue: 20))])
        XCTAssertTrue(try GraphReferenceColorPlan.clear(snapshot: state.snapshot).updates.isEmpty)
        try state.selectGraph(nodes: ["a"], edges: ["unowned"])
        XCTAssertTrue(GraphReferenceColorPlan.canColorize(snapshot: state.snapshot))
        XCTAssertThrowsError(
            try GraphReferenceColorPlan.autoColor(
                snapshot: state.snapshot, raster: raster(), layout: layout(state.snapshot))
        ) {
            XCTAssertEqual($0 as? ReferenceColorError, .unresolvableOwner("unowned"))
        }
    }

    func testPositionAndRadiusLocksDoNotChangeRgbPlan() throws {
        var state = try state()
        try state.selectGraph(nodes: ["a", "c"], edges: [])
        let before = try GraphReferenceColorPlan.autoColor(
            snapshot: state.snapshot, raster: raster(), layout: layout(state.snapshot))
        for lock in EditingConstraint.allCases { state.setLock(lock, isLocked: true) }
        let after = try GraphReferenceColorPlan.autoColor(
            snapshot: state.snapshot, raster: raster(), layout: layout(state.snapshot))
        XCTAssertEqual(before.updates, after.updates)
    }

    func testMissingAndAmbiguousComponentOwnersRejectWholePlanWithoutMutation() throws {
        for (extra, omit, expected): (String, Bool, ReferenceColorError) in [
            ("", true, .unresolvableOwner("a")),
            ("<component id='otherq' linkDataType='partId' linkData='q'/>", false, .ambiguousOwner("q")),
        ] {
            var state = try state(extraComponents: extra, omitPComponent: omit)
            try state.selectGraph(nodes: ["a", "d"], edges: [])
            let before = state.snapshot
            XCTAssertThrowsError(
                try GraphReferenceColorPlan.autoColor(snapshot: before, raster: raster(), layout: layout(before))
            ) {
                XCTAssertEqual($0 as? ReferenceColorError, expected)
            }
            XCTAssertThrowsError(try GraphReferenceColorPlan.clear(snapshot: before)) {
                XCTAssertEqual($0 as? ReferenceColorError, expected)
            }
            XCTAssertEqual(state.snapshot.document.encoded(), before.document.encoded())
            XCTAssertFalse(state.snapshot.canUndo)
        }
    }

    func testReadOnlyPartNeedsNoMutableComponentResolution() throws {
        var state = try state(partState: "locked='true'", omitPComponent: true)
        try state.selectGraph(nodes: ["a"], edges: [])
        let snapshot = state.snapshot
        let plan = try GraphReferenceColorPlan.autoColor(snapshot: snapshot, raster: raster(), layout: layout(snapshot))
        XCTAssertTrue(plan.updates.isEmpty)
        XCTAssertEqual(plan.skippedReadOnlyObjects, 1)
        XCTAssertEqual(try GraphReferenceColorPlan.clear(snapshot: snapshot).skippedReadOnlyObjects, 1)
    }

    func testEveryByteValueContributesOneDistinctColorWithoutNarrowAccumulatorOverflow() throws {
        // 256 ordinary pixels/samples exercise channel extremes; this is not an allocation-pressure fixture.
        let nodes = (0..<256).map {
            "<node id='n\($0)' partId='p' x='\(Double($0) + 0.25)' y='.5' z='0' radius='.01'/>"
        }.joined()
        var state = try EditorState(
            document: Dust3DDocument(
                snapshotXML: Data(
                    "<canvas><nodes>\(nodes)</nodes><edges/><parts><part id='p'/></parts><components><component id='c' linkDataType='partId' linkData='p'/></components></canvas>"
                        .utf8)))
        try state.selectGraph(nodes: Set((0..<256).map { "n\($0)" }), edges: [])
        let raster = try ReferenceColorRaster(
            width: 256, height: 1, rowStride: 1024,
            pixels: Data((0..<256).flatMap { [UInt8($0), UInt8(255 - $0), 200, 0] }))
        let projection = CanvasProjection(
            bounds: .init(nodes: state.snapshot.nodes, referenceImageAspectRatio: 256), plane: .front, width: 700,
            height: 500)
        let layout = try ReferenceColorSamplingLayout(
            referenceSize: .init(width: 256, height: 1), projection: projection)
        let plan = try GraphReferenceColorPlan.autoColor(snapshot: state.snapshot, raster: raster, layout: layout)
        XCTAssertEqual(plan.updates, [.init(componentID: "c", color: .init(red: 127, green: 127, blue: 200))])
        XCTAssertEqual(plan.skippedOutsideObjects, 0)
    }

    func testInconsistentSnapshotEdgeCannotPublishAPartialPlan() throws {
        var state = try state()
        try state.selectGraph(nodes: ["a"], edges: ["ab"])
        let current = state.snapshot
        // An adapter can hold a structurally inconsistent presentation value; planning must fail closed.
        let inconsistent = EditorSnapshot(
            documentIdentity: current.documentIdentity, document: current.document, nodes: current.nodes,
            edges: [.init(id: "ab", fromID: "a", toID: "absent", partID: "q")], parts: current.parts,
            componentTree: current.componentTree, rigSettings: current.rigSettings,
            colorImageAssets: current.colorImageAssets, selectedComponentIDs: current.selectedComponentIDs,
            componentRevealHint: current.componentRevealHint, origin: current.origin, selectedID: current.selectedID,
            selectedIDs: current.selectedIDs, selectedEdgeIDs: current.selectedEdgeIDs,
            canInsertSelectedEdgeMidpoints: false, canReduceSelectedNodes: false,
            selectedPartID: current.selectedPartID,
            canUndo: current.canUndo, canRedo: current.canRedo, locks: current.locks,
            documentRevision: current.documentRevision, previewIdentity: current.previewIdentity,
            constraintRevision: current.constraintRevision, selectionRevision: current.selectionRevision)
        XCTAssertThrowsError(
            try GraphReferenceColorPlan.autoColor(snapshot: inconsistent, raster: raster(), layout: layout(current))
        ) {
            XCTAssertEqual($0 as? ReferenceColorError, .unresolvableOwner("ab"))
        }
        XCTAssertEqual(state.snapshot.document.encoded(), current.document.encoded())
        XCTAssertFalse(state.snapshot.canUndo)
    }

    func testPlannerCommandsUseOneDocumentColorBatchAndEmptyPlansNeedNoCommand() throws {
        var state = try state()
        try state.selectGraph(nodes: ["c"], edges: ["ab"])
        let plan = try GraphReferenceColorPlan.autoColor(
            snapshot: state.snapshot, raster: raster(), layout: layout(state.snapshot))
        XCTAssertEqual(plan.commands.count, 1)
        guard case .setComponentColors(let updates) = try XCTUnwrap(plan.commands.first) else {
            return XCTFail("Graph colorization must submit one indexed document batch")
        }
        XCTAssertEqual(updates, plan.updates.map { .init(componentID: $0.componentID, color: $0.color) })
        try state.selectGraph(nodes: [], edges: ["ab"])
        XCTAssertTrue(try GraphReferenceColorPlan.clear(snapshot: state.snapshot).commands.isEmpty)
        try state.selectGraph(nodes: ["outside"], edges: [])
        XCTAssertTrue(
            try GraphReferenceColorPlan.autoColor(
                snapshot: state.snapshot, raster: raster(), layout: layout(state.snapshot)
            ).commands.isEmpty)
    }
}
