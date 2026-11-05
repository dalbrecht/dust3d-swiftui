import Dust3DDocument
import Foundation
import XCTest

final class ComponentPartRoleTests: XCTestCase {
    private func document(_ components: String, targets: String = "") throws -> Dust3DDocument {
        let model = Data(
            "<canvas><nodes/><edges/><parts><part id='p' locked='true' future='p' \(targets)/><part id='q' visible='false' disabled='true' \(targets)/></parts><components>\(components)</components></canvas>"
                .utf8)
        let header = "<ds3><model name='model.xml' offset='0' size='\(model.count)'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model)
    }
    private let a = "<component id='a' linkDataType='partId' linkData='p'/>"
    private let b = "<component id='b' linkDataType='partId' linkData='q'/>"

    func testRoleCommandsRequireExactComponentAndPartOwnershipBeforeAnyEdit() throws {
        let actualComponent = "owner-cafe\u{301}"
        let componentAlias = "owner-caf\u{e9}"
        let actualPart = "cafe\u{301}"
        let partAlias = "caf\u{e9}"
        let prefix = "<canvas><nodes/><edges/><parts><part id='cafe&#769;' future='keep'/></parts><components>"
        let owner = "<component id='owner-cafe&#769;' linkDataType='partId' linkData='cafe&#769;'/>"
        let danglingRow = "<component id='dangling' linkDataType='partId' linkData='caf&#233;'/>"
        let suffix = "</components></canvas>"
        let ownerOnly = try Dust3DDocument(snapshotXML: Data((prefix + owner + suffix).utf8))
        let danglingOnly = try Dust3DDocument(snapshotXML: Data((prefix + danglingRow + suffix).utf8))
        let original = try Dust3DDocument(snapshotXML: Data((prefix + owner + danglingRow + suffix).utf8))
        for (source, requested, expected) in [
            (ownerOnly, [componentAlias], DocumentError.missingComponent(componentAlias)),
            (ownerOnly, [actualComponent, componentAlias], DocumentError.missingComponent(componentAlias)),
            (danglingOnly, ["dangling"], DocumentError.missingPart(partAlias)),
        ] {
            var history = DocumentHistory(document: source)
            XCTAssertThrowsError(
                try history.apply(
                    .setComponentPartRoles(componentIDs: requested, target: .cutFace, newGroupID: nil))
            ) {
                XCTAssertEqual($0 as? DocumentError, expected)
            }
            XCTAssertEqual(history.document.encoded(), source.encoded())
            XCTAssertFalse(history.canUndo)
        }
        var history = DocumentHistory(document: original)
        try history.apply(.setComponentPartRoles(componentIDs: [actualComponent], target: .cutFace, newGroupID: nil))
        let part = try XCTUnwrap(history.document.editorContents().parts.first)
        XCTAssertEqual(Data(part.id.utf8), Data(actualPart.utf8))
        XCTAssertEqual(part.target, .cutFace)
        let dangling = try XCTUnwrap(history.document.components().first { $0.id == "dangling" })
        XCTAssertEqual(dangling.partID.map { Data($0.utf8) }, Data(partAlias.utf8))
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), original.encoded())
    }

    func testRootStitchingGroupsInDocumentOrderAndUndoesExactly() throws {
        let source = try document(a + "<component id='other'/>" + b)
        var history = DocumentHistory(document: source)
        try history.apply(.setComponentPartRoles(componentIDs: ["b", "a"], target: .stitchingLine, newGroupID: "g"))
        let changed = history.document
        XCTAssertEqual(try changed.components().map(\.id), ["g", "a", "b", "other"])
        XCTAssertEqual(try changed.components().first?.childIDs, ["a", "b"])
        XCTAssertTrue(try changed.editorContents().parts.allSatisfy { $0.target == .stitchingLine })
        XCTAssertEqual(try Dust3DDocument(data: changed.encoded()).components(), try changed.components())
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), source.encoded())
        XCTAssertFalse(history.canUndo)
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.document.encoded(), changed.encoded())
    }

    func testExistingGroupReuseIncludesUnselectedSiblingAndSameRoleIsByteNoOp() throws {
        let source = try document(
            "<component id='g' future='retained'>" + a + "<component id='other'/>" + b + "</component>",
            targets: "target='StitchingLoop'")
        let changed = try source.applying(
            .setComponentPartRoles(componentIDs: ["a", "b"], target: .stitchingLoop, newGroupID: nil))
        XCTAssertEqual(changed.encoded(), source.encoded())
        let plan = try ComponentPartRolePlan(
            components: source.components(), parts: source.editorContents().parts, componentIDs: ["g", "b", "a"],
            target: .stitchingLoop)
        XCTAssertEqual(plan.partIDs, ["p", "q"])
        XCTAssertEqual(plan.revealGroupID, "g")
        XCTAssertFalse(plan.requiresNewGroup)
    }

    func testCrossParentMetadataAllowedButStitchingRejectsAtomically() throws {
        let source = try document("<component id='g'>" + a + "</component>" + b)
        for target in [PartTarget.model, .cutFace] {
            XCTAssertNoThrow(
                try source.applying(.setComponentPartRoles(componentIDs: ["a", "b"], target: target, newGroupID: nil)))
        }
        for target in [PartTarget.stitchingLine, .stitchingLoop] {
            var history = DocumentHistory(document: source)
            XCTAssertThrowsError(
                try history.apply(
                    .setComponentPartRoles(componentIDs: ["a", "b"], target: target, newGroupID: "fresh")))
            XCTAssertEqual(history.document.encoded(), source.encoded())
            XCTAssertFalse(history.canUndo)
        }
    }
    func testAllRolesIgnoreSelectedGroupsAndPreservePartFlagsAndOpaqueAttributes() throws {
        let source = try document("<component id='g'>" + a + "</component>" + b)
        for target in PartTarget.allCases {
            let changed = try source.applying(
                .setComponentPartRoles(componentIDs: ["g", "b"], target: target, newGroupID: nil))
            let parts = try changed.editorContents().parts
            XCTAssertEqual(parts.first { $0.id == "p" }?.target, .model)
            XCTAssertEqual(parts.first { $0.id == "q" }?.target, target)
            let xml = try XMLDocument(data: changed.modelXML)
            XCTAssertEqual(try xml.nodes(forXPath: "//part[@id='p']/@locked").first?.stringValue, "true")
            XCTAssertEqual(try xml.nodes(forXPath: "//part[@id='p']/@future").first?.stringValue, "p")
            XCTAssertEqual(try xml.nodes(forXPath: "//part[@id='q']/@visible").first?.stringValue, "false")
            XCTAssertEqual(try xml.nodes(forXPath: "//part[@id='q']/@disabled").first?.stringValue, "true")
        }
    }

    func testMissingAmbiguousDuplicateAndInvalidFreshIdentitiesRejectWithoutPartialChanges() throws {
        let source = try document(a + b)
        for (ids, group) in [
            (["a", "missing"], "new"), (["a", "a"], "new"), (["a", "b"], "a"), (["a", "b"], "p"),
            (["a", "b"], "bad id"), (["a", "b"], ""),
        ] {
            var history = DocumentHistory(document: source)
            XCTAssertThrowsError(
                try history.apply(.setComponentPartRoles(componentIDs: ids, target: .stitchingLine, newGroupID: group)))
            XCTAssertEqual(history.document.encoded(), source.encoded())
            XCTAssertFalse(history.canUndo)
        }
        for components in [
            a + b + "<component id='alias' linkDataType='partId' linkData='p'/>",
            a + "<component id='b' linkDataType='partId' linkData='missing'/>",
        ] {
            let invalid = try document(components)
            XCTAssertThrowsError(
                try invalid.applying(
                    .setComponentPartRoles(componentIDs: ["a", "b"], target: .cutFace, newGroupID: nil)))
        }
        XCTAssertThrowsError(
            try source.applying(
                .setComponentPartRoles(componentIDs: ["a", "b"], target: .stitchingLoop, newGroupID: nil)))
        XCTAssertThrowsError(
            try source.applying(.setComponentPartRoles(componentIDs: ["a"], target: .model, newGroupID: "unneeded")))
        XCTAssertThrowsError(
            try source.applying(.setComponentPartRoles(componentIDs: [], target: .model, newGroupID: nil)))
    }

    func testLinkedParentRejectsMultiStitchButSingleAndMetadataOnlyRolesRemainAvailable() throws {
        let source = try document(
            "<component id='opaque' linkDataType='future' linkData='retained'>" + a + b + "</component>")
        for target in PartTarget.allCases {
            XCTAssertNoThrow(
                try source.applying(.setComponentPartRoles(componentIDs: ["a"], target: target, newGroupID: nil)))
        }
        XCTAssertNoThrow(
            try source.applying(.setComponentPartRoles(componentIDs: ["a", "b"], target: .cutFace, newGroupID: nil)))
        XCTAssertThrowsError(
            try source.applying(
                .setComponentPartRoles(componentIDs: ["a", "b"], target: .stitchingLoop, newGroupID: nil)))
    }

    func testAlreadyStitchingRootSiblingsStillGroupAndBothPreviewInputsAdvance() throws {
        let source = try document(a + b, targets: "target='StitchingLine'")
        var history = DocumentHistory(document: source)
        let before = history.previewIdentity
        try history.apply(.setComponentPartRoles(componentIDs: ["a", "b"], target: .stitchingLine, newGroupID: "g"))
        XCTAssertNotEqual(history.previewIdentity.geometry, before.geometry)
        XCTAssertNotEqual(history.previewIdentity.materials, before.materials)
        XCTAssertEqual(try history.document.components().first?.childIDs, ["a", "b"])
    }

    func testExistingComponentQuotaAllowsReuseButRejectsFreshGroup() throws {
        let siblings = (0..<9998).map { "<component id='extra\($0)'/>" }.joined()
        let fullRoot = try document(a + b + siblings)
        XCTAssertThrowsError(
            try fullRoot.applying(
                .setComponentPartRoles(componentIDs: ["a", "b"], target: .stitchingLine, newGroupID: "fresh"))
        ) {
            XCTAssertEqual($0 as? DocumentError, .limitExceeded)
        }
        let fullGroup = try document(
            "<component id='g'>" + a + b + "</component>" + (0..<9997).map { "<component id='extra\($0)'/>" }.joined())
        let changed = try fullGroup.applying(
            .setComponentPartRoles(componentIDs: ["a", "b"], target: .stitchingLine, newGroupID: nil))
        XCTAssertEqual(try changed.components().count, 10000)
        XCTAssertEqual(try changed.components().first?.childIDs, ["a", "b"])
        XCTAssertThrowsError(
            try ComponentPartRolePlan(
                components: [], parts: [], componentIDs: Array(repeating: "id", count: 10001), target: .model)
        ) {
            XCTAssertEqual($0 as? DocumentError, .limitExceeded)
        }
    }

    func testSeveralHundredOwnersUseOneAtomicHistoryEntryAndMatchSingleRoleSemantics() throws {
        let parts = (0..<250).map { "<part id='p\($0)' future='retained'/>" }.joined()
        let components = (0..<250).map { "<component id='c\($0)' linkDataType='partId' linkData='p\($0)'/>" }.joined()
        let source = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes/><edges/><parts>\(parts)</parts><components>\(components)</components></canvas>".utf8))
        var history = DocumentHistory(document: source)
        try history.apply(
            .setComponentPartRoles(
                componentIDs: (0..<250).reversed().map { "c\($0)" }, target: .cutFace, newGroupID: nil))
        XCTAssertTrue(try history.document.editorContents().parts.allSatisfy { $0.target == .cutFace })
        XCTAssertEqual(try history.document.components().map(\.id), try source.components().map(\.id))
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.document.encoded(), source.encoded())
        XCTAssertFalse(history.canUndo)
        var tiny = DocumentHistory(document: source, maximumUndoBytes: 1)
        XCTAssertThrowsError(
            try tiny.apply(.setComponentPartRoles(componentIDs: ["c0"], target: .cutFace, newGroupID: nil)))
        XCTAssertEqual(tiny.document.encoded(), source.encoded())
    }

    func testPlannerRejectsDuplicateSourceIdentitiesAndHasStableValueEquality() throws {
        let source = try document(a + b)
        let components = try source.components()
        let parts = try source.editorContents().parts
        XCTAssertThrowsError(
            try ComponentPartRolePlan(
                components: components + components, parts: parts, componentIDs: ["a"], target: .model)
        ) {
            XCTAssertEqual($0 as? DocumentError, .invalidComponent)
        }
        let forward = try ComponentPartRolePlan(
            components: components, parts: parts, componentIDs: ["a", "b"], target: .stitchingLine)
        let backward = try ComponentPartRolePlan(
            components: components, parts: parts, componentIDs: ["b", "a"], target: .stitchingLine)
        XCTAssertEqual(forward, backward)
        XCTAssertEqual(forward.target, .stitchingLine)
        XCTAssertThrowsError(
            try ComponentPartRolePlan(components: components, parts: parts, componentIDs: ["absent"], target: .model))
    }

}
