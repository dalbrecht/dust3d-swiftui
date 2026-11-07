import Dust3DDocument
import Foundation
import XCTest

@testable import Dust3DEditorModel

#if canImport(FoundationXML)
    import FoundationXML
#endif

final class CanvasPartIsolationTests: XCTestCase {
    private func document(parts: String? = nil, components: String? = nil) throws -> Dust3DDocument {
        let nodes =
            parts == nil
            ? """
            <node id='na' partId='a' x='0' y='0' z='0' radius='.1'/>
            <node id='nb' partId='a' x='1' y='0' z='0' radius='.1'/>
            <node id='nc' partId='c' x='2' y='0' z='0' radius='.1'/>
            <node id='unowned' x='3' y='0' z='0' radius='.1'/>
            """ : ""
        let edges =
            parts == nil
            ? """
            <edge id='ab' partId='a' from='na' to='nb'/>
            <edge id='foreign' partId='c' from='na' to='nb'/>
            <edge id='unownedEdge' from='na' to='nb'/>
            """ : ""
        return try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas future='retained'><nodes>\(nodes)</nodes><edges>\(edges)</edges>
                <parts>\(parts ?? "<part id='a' visible='false' locked='true' future='keep'/><part id='b' disabled='true'/><part id='c'/><part id='orphan'/><part id='d'/>")</parts>
                <components>\(components ?? "<component id='g'><component id='ca' linkDataType='partId' linkData='a'/><component id='nested'><component id='cb' linkDataType='partId' linkData='b'/></component></component><component id='hybrid' linkDataType='partId' linkData='c'><component id='cd' linkDataType='partId' linkData='d'/></component>")</components></canvas>
                """.utf8))
    }

    private func batch(_ target: CanvasPartIsolationTarget, in snapshot: EditorSnapshot) throws -> ([String], Bool) {
        let commands = try target.commands(in: snapshot)
        XCTAssertEqual(commands.count, 1)
        guard case .setPartsState(let ids, let property, let value) = try XCTUnwrap(commands.first) else {
            XCTFail("Expected one visibility batch")
            return ([], false)
        }
        XCTAssertEqual(property, .visible)
        return (ids, value)
    }

    func testNestedGroupHidesOutsidePartsInSourceOrderWithoutChangingInsideFlags() throws {
        var state = try EditorState(document: document())
        try state.selectComponent("g")
        let before = state.snapshot
        let target = CanvasPartIsolationTarget(snapshot: before)
        XCTAssertTrue(target.isAvailable)
        XCTAssertNil(target.unavailableReason)
        XCTAssertEqual(target.title, "Hide Other Parts in Canvas")
        let (ids, value) = try batch(target, in: before)
        XCTAssertEqual(ids, ["c", "orphan", "d"])
        XCTAssertFalse(value)
        try state.apply(target.commands(in: before))
        XCTAssertEqual(state.snapshot.parts.filter(\.isVisible).map(\.id), ["b"])
        XCTAssertTrue(state.snapshot.parts.first { $0.id == "a" }?.isLocked == true)
        XCTAssertTrue(state.snapshot.parts.first { $0.id == "b" }?.isDisabled == true)
        XCTAssertEqual(state.snapshot.previewIdentity, before.previewIdentity)
        let xml = try XMLDocument(data: state.snapshot.document.modelXML)
        let preserved = try XCTUnwrap(try xml.nodes(forXPath: "/canvas/parts/part[@id='a']").first as? XMLElement)
        XCTAssertEqual(preserved.attribute(forName: "future")?.stringValue, "keep")
    }

    func testLinkedPartStopsTraversalEvenWhenItHasHybridChildren() throws {
        let snapshot = try EditorState(document: document()).snapshot
        let target = CanvasPartIsolationTarget(snapshot: snapshot, componentID: "hybrid")
        let (ids, value) = try batch(target, in: snapshot)
        XCTAssertEqual(ids, ["a", "b", "orphan", "d"])
        XCTAssertFalse(value)
    }

    func testNoVisibleOutsidePartsSwitchesToShowAllIncludingHiddenInside() throws {
        let parts =
            "<part id='a' visible='false'/><part id='b'/><part id='c' visible='false'/><part id='orphan' visible='false'/><part id='d' visible='false'/>"
        let snapshot = try EditorState(document: document(parts: parts)).snapshot
        let target = CanvasPartIsolationTarget(snapshot: snapshot, componentID: "g")
        XCTAssertEqual(target.title, "Show All Parts in Canvas")
        XCTAssertTrue(target.isAvailable)
        let (ids, value) = try batch(target, in: snapshot)
        XCTAssertEqual(ids, ["a", "b", "c", "orphan", "d"])
        XCTAssertTrue(value)
    }

    func testExplicitShowAllNeedsNoSelectionAndIgnoresUnsupportedComponentMembership() throws {
        let snapshot = try EditorState(document: document(components: "<component id='dup'/><component id='dup'/>"))
            .snapshot
        XCTAssertNotNil(snapshot.componentTree.failureDescription)
        let target = CanvasPartIsolationTarget(snapshot: snapshot, showAll: true)
        XCTAssertTrue(target.isAvailable)
        XCTAssertEqual(target.title, "Show All Parts in Canvas")
        XCTAssertTrue(try batch(target, in: snapshot).1)
        let allVisible = try EditorState(
            document: document(parts: "<part id='a'/><part id='b'/><part id='c'/><part id='orphan'/><part id='d'/>")
        )
        .snapshot
        let noop = CanvasPartIsolationTarget(snapshot: allVisible, showAll: true)
        XCTAssertFalse(noop.isAvailable)
        XCTAssertNotNil(noop.unavailableReason)
        XCTAssertTrue(try noop.commands(in: allVisible).isEmpty)
    }

    func testImplicitPartNodeAndActualStoredEdgeOwnerResolveWithoutEndpointInference() throws {
        for mode in 0..<4 {
            var state = try EditorState(document: document())
            switch mode {
            case 0: try state.selectPart("a")
            case 1: try state.select("na")
            case 2: try state.selectGraph(nodes: ["na", "nb"], edges: ["ab"])
            default: try state.selectEdge("foreign")
            }
            let snapshot = state.snapshot
            let target = CanvasPartIsolationTarget(snapshot: snapshot)
            XCTAssertTrue(target.isAvailable)
            let (ids, _) = try batch(target, in: snapshot)
            XCTAssertEqual(ids, mode == 3 ? ["a", "b", "orphan", "d"] : ["b", "c", "orphan", "d"])
        }
    }

    func testExplicitPartCapturesItsOwnMembershipAndNeverFallsBackToSelection() throws {
        var state = try EditorState(document: document())
        try state.selectComponent("hybrid")
        let snapshot = state.snapshot
        let target = CanvasPartIsolationTarget(snapshot: snapshot, partID: "a")
        XCTAssertTrue(target.isAvailable)
        XCTAssertEqual(try batch(target, in: snapshot).0, ["b", "c", "orphan", "d"])
        for part in ["absent", "orphan"] {
            let invalid = CanvasPartIsolationTarget(snapshot: snapshot, partID: part)
            XCTAssertFalse(invalid.isAvailable)
            XCTAssertThrowsError(try invalid.commands(in: snapshot))
        }
        let ambiguous = CanvasPartIsolationTarget(snapshot: snapshot, componentID: "hybrid", partID: "a")
        XCTAssertFalse(ambiguous.isAvailable)
        XCTAssertThrowsError(try ambiguous.commands(in: snapshot))
    }

    func testAmbiguousSelectionsAndMissingOrRepeatedOwnersNeverGuess() throws {
        for mode in 0..<6 {
            var state = try EditorState(document: document())
            switch mode {
            case 0: break
            case 1: try state.selectComponents(["g", "hybrid"])
            case 2: try state.selectGraph(nodes: ["na", "nc"], edges: [])
            case 3: try state.select("unowned")
            case 4: try state.selectEdge("unownedEdge")
            default: try state.selectPart("orphan")
            }
            let snapshot = state.snapshot
            let target = CanvasPartIsolationTarget(snapshot: snapshot)
            XCTAssertFalse(target.isAvailable)
            XCTAssertNotNil(target.unavailableReason)
            XCTAssertThrowsError(try target.commands(in: snapshot)) { XCTAssertTrue($0 is CanvasPartIsolationError) }
        }
        var shared = try EditorState(
            document: document(
                components:
                    "<component id='one' linkDataType='partId' linkData='a'/><component id='two' linkDataType='partId' linkData='a'/>"
            ))
        try shared.selectPart("a")
        let snapshot = shared.snapshot
        XCTAssertFalse(CanvasPartIsolationTarget(snapshot: snapshot).isAvailable)
        XCTAssertFalse(CanvasPartIsolationTarget(snapshot: snapshot, partID: "a").isAvailable)
        XCTAssertTrue(CanvasPartIsolationTarget(snapshot: snapshot, componentID: "one").isAvailable)
    }

    func testUnsupportedVisitedLinksAndBrokenHierarchyExposeOriginalCause() throws {
        for components in [
            "<component id='bad' linkDataType='future' linkData='opaque'/>",
            "<component id='bad' linkDataType='partId' linkData='absent'/>",
            "<component id='bad' linkData='opaque'/>",
            "<component id='bad'><component id='opaque' linkDataType='future' linkData='opaque'/></component>",
            "<component id='bad'/><component id='bad'/>",
        ] {
            let snapshot = try EditorState(document: document(components: components)).snapshot
            let target = CanvasPartIsolationTarget(snapshot: snapshot, componentID: "bad")
            XCTAssertFalse(target.isAvailable)
            let reason = try XCTUnwrap(target.unavailableReason)
            XCTAssertFalse(reason.isEmpty)
            if let original = snapshot.componentTree.failureDescription { XCTAssertTrue(reason.contains(original)) }
            XCTAssertThrowsError(try target.commands(in: snapshot)) { XCTAssertTrue($0 is CanvasPartIsolationError) }
        }
        let snapshot = try EditorState(document: document(components: "<component id='empty'/>")).snapshot
        XCTAssertFalse(CanvasPartIsolationTarget(snapshot: snapshot, componentID: "empty").isAvailable)
        XCTAssertFalse(CanvasPartIsolationTarget(snapshot: snapshot, componentID: "absent").isAvailable)
    }

    func testExactUnicodeIdentityDoesNotResolveCanonicalAliases() throws {
        for (part, link) in [("é", "e\u{301}"), ("e\u{301}", "é")] {
            let snapshot = try EditorState(
                document: document(
                    parts: "<part id='\(part)'/><part id='outside'/>",
                    components: "<component id='leaf' linkDataType='partId' linkData='\(link)'/>")
            ).snapshot
            let target = CanvasPartIsolationTarget(snapshot: snapshot, componentID: "leaf")
            XCTAssertFalse(target.isAvailable)
            XCTAssertThrowsError(try target.commands(in: snapshot))
        }
        let snapshot = try EditorState(
            document: document(
                parts: "<part id='p'/><part id='outside'/>",
                components: "<component id='é' linkDataType='partId' linkData='p'/>")
        ).snapshot
        XCTAssertFalse(CanvasPartIsolationTarget(snapshot: snapshot, componentID: "e\u{301}").isAvailable)
        XCTAssertTrue(CanvasPartIsolationTarget(snapshot: snapshot, componentID: "é").isAvailable)
    }

    func testCapturedTargetRejectsSelectionConstraintDocumentAndWindowABA() throws {
        for mode in 0..<4 {
            let original = try document()
            var state = try EditorState(document: original)
            try state.selectComponent("g")
            let target = CanvasPartIsolationTarget(snapshot: state.snapshot)
            switch mode {
            case 0:
                try state.selectComponent("hybrid")
                try state.selectComponent("g")
            case 1:
                state.setLock(.x, isLocked: true)
                state.setLock(.x, isLocked: false)
            case 2:
                try state.apply([.setPartName(id: "a", name: "Changed")])
                try state.undo()
            default:
                var other = try EditorState(document: original)
                try other.selectComponent("g")
                XCTAssertFalse(target.isCurrent(in: other.snapshot))
                XCTAssertThrowsError(try target.commands(in: other.snapshot)) {
                    XCTAssertEqual($0 as? CanvasPartIsolationError, .staleTarget)
                }
                continue
            }
            XCTAssertFalse(target.isCurrent(in: state.snapshot))
            XCTAssertThrowsError(try target.commands(in: state.snapshot)) {
                XCTAssertEqual($0 as? CanvasPartIsolationError, .staleTarget)
            }
        }
    }

    func testValidBulkScopeIsNotLimitedTo128Parts() throws {
        let parts = (0..<130).map { "<part id='p\($0)'/>" }.joined()
        let snapshot = try EditorState(
            document: document(
                parts: parts, components: "<component id='leaf' linkDataType='partId' linkData='p0'/>")
        ).snapshot
        let target = CanvasPartIsolationTarget(snapshot: snapshot, componentID: "leaf")
        let (ids, value) = try batch(target, in: snapshot)
        XCTAssertEqual(ids.count, 129)
        XCTAssertEqual(ids.first, "p1")
        XCTAssertEqual(ids.last, "p129")
        XCTAssertFalse(value)
    }
}
