import Dust3DDocument
import Foundation
import XCTest

final class ComponentWrappingBatchTests: XCTestCase {
    private func document() throws -> Dust3DDocument {
        let xml = Data(
            "<canvas><nodes/><edges/><parts/><components><component id='a' wrap='Skin' future='keep' wrapDrape='opaque'/><component id='b' wrap='Cloth'/><component id='c' wrap='Future' wrapPattern='FuturePattern'/><component id='d'/></components></canvas>"
                .utf8)
        let header = "<ds3><model name='model.xml' offset='0' size='\(xml.count)'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + xml)
    }
    func testExplicitScalarAppliesAcrossAllModesWithoutNormalizingThem() throws {
        let original = try document()
        let updated = try original.applying(
            .editComponentWrapping(ids: ["a", "b", "c", "d"], edit: .scalar(.drape, 0.25)))
        let rows = try updated.components()
        XCTAssertEqual(rows.map { $0.wrapping.mode }, [ComponentWrapMode.skin, .cloth, nil, ComponentWrapMode.none])
        XCTAssertTrue(rows.allSatisfy { $0.wrapping.scalarValue(.drape) == 0.25 })
        XCTAssertEqual(try Dust3DDocument(data: updated.encoded()).encoded(), updated.encoded())
        XCTAssertEqual(
            try original.applying(.editComponentWrapping(ids: ["a", "b"], edit: .mode(.none))).components().prefix(2)
                .map { $0.wrapping.mode }, [ComponentWrapMode.none, ComponentWrapMode.none])
    }
    func testMixedModeEditAuthorsChangedValuesWithoutRewritingUnchangedDefaults() throws {
        let source = try document()
        let edit = DocumentCommand.editComponentWrapping(ids: ["a", "b"], edit: .scalar(.offset, 0))
        let changed = try source.applying(edit)
        let xml = try XMLDocument(data: changed.modelXML)
        let a = try XCTUnwrap(xml.nodes(forXPath: "//component[@id='a']").first as? XMLElement)
        let b = try XCTUnwrap(xml.nodes(forXPath: "//component[@id='b']").first as? XMLElement)
        XCTAssertNil(a.attribute(forName: "wrapOffset"))
        XCTAssertEqual(b.attribute(forName: "wrapOffset")?.stringValue, "0.0")
        XCTAssertEqual(try changed.applying(edit).encoded(), changed.encoded())
    }

    func testClearWrappingSettingsRemovesOverridesAndKeepsUnrelatedAttributes() throws {
        let source = try Dust3DDocument(
            snapshotXML: Data(
                """
                <canvas xmlns:other='urn:other'><components>
                    <component id='a' wrap='Cloth' wrapBindTo='body' wrapFaces='400' wrapPattern='Spots'
                        wrapFuture='opaque' future='keep' other:wrapValue='keep'/>
                    <component id='b' wrapDrape='0.5'/>
                    <component id='body' wrap='Skin' wrapFaces='900'/>
                </components></canvas>
                """.utf8))
        let clear = DocumentCommand.editComponentWrapping(ids: ["a", "b"], edit: .clearSettings)
        let cleared = try source.applying(clear)
        let xml = try XMLDocument(data: cleared.modelXML)
        let a = try XCTUnwrap(xml.nodes(forXPath: "/canvas/components/component[@id='a']").first as? XMLElement)
        XCTAssertEqual(a.attribute(forName: "future")?.stringValue, "keep")
        XCTAssertEqual(a.attribute(forName: "other:wrapValue")?.stringValue, "keep")
        XCTAssertFalse(a.attributes?.contains { ($0.name ?? "").hasPrefix("wrap") } ?? true)
        XCTAssertEqual(try cleared.components().last?.wrapping.targetFaces, 900)
        XCTAssertEqual(try cleared.applying(clear).encoded(), cleared.encoded())
        XCTAssertEqual(try Dust3DDocument(data: cleared.encoded()).encoded(), cleared.encoded())

        let enabled = try cleared.applying(.setComponentWrapMode(id: "a", mode: .cloth))
        let fresh = try XCTUnwrap(try enabled.components().first?.wrapping)
        XCTAssertEqual(fresh.targetFaces, 1200)
        XCTAssertEqual(fresh.surfaceDetails.pattern, ComponentSurfacePattern.none)
        XCTAssertEqual(fresh.binding, .absent)
    }

    func testLateMissingAndDuplicateOwnersRejectWithoutChangingArchive() throws {
        let source = try document()
        let bytes = source.encoded()
        XCTAssertThrowsError(
            try source.applying(.editComponentWrapping(ids: Array(repeating: "a", count: 10_001), edit: .mode(.cloth)))
        ) {
            XCTAssertEqual($0 as? DocumentError, .limitExceeded)
        }
        for ids in [["a", "missing"], ["a", "a"], []] {
            XCTAssertThrowsError(try source.applying(.editComponentWrapping(ids: ids, edit: .keepChildren(true))))
        }
        XCTAssertEqual(source.encoded(), bytes)
    }
    // Sequential Foundation XML serialization adds structural whitespace each time. Compare the full
    // fixture tree after removing only formatting-only text, retaining all attributes and opaque nodes.
    private func tree(_ document: Dust3DDocument) throws -> Data {
        let xml = try XMLDocument(data: document.modelXML)
        func strip(_ node: XMLNode) {
            for child in node.children ?? [] {
                if child.kind == .text
                    && (child.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    child.detach()
                } else {
                    strip(child)
                }
            }
        }
        strip(xml)
        return xml.xmlData()
    }
    func testEveryFieldMatchesIndependentSingletonEditsIncludingModeDefaults() throws {
        let source = try document()
        let edits: [(ComponentWrappingEdit, (String) -> DocumentCommand)] = [
            (.mode(.none), { .setComponentWrapMode(id: $0, mode: .none) }),
            (.mode(.cloth), { .setComponentWrapMode(id: $0, mode: .cloth) }),
            (.keepChildren(true), { .setComponentWrapKeepChildren(id: $0, value: true) }),
            (.keepChildren(false), { .setComponentWrapKeepChildren(id: $0, value: false) }),
            (.targetFaces(1200), { .setComponentWrapFaces(id: $0, faces: 1200) }),
            (.targetFaces(1600), { .setComponentWrapFaces(id: $0, faces: 1600) }),
            (.surfacePattern(.spots), { .setComponentSurfacePattern(id: $0, pattern: .spots) }),
            (.surfacePattern(.none), { .setComponentSurfacePattern(id: $0, pattern: .none) }),
            (
                .surfaceInk(.init(red: 2, green: 4, blue: 8)),
                { .setComponentSurfaceColor(id: $0, color: .init(red: 2, green: 4, blue: 8)) }
            ),
            (.surfaceInk(nil), { .setComponentSurfaceColor(id: $0, color: nil) }),
        ]
        for (edit, individual) in edits {
            var expected = source
            for id in ["a", "b", "c", "d"] { expected = try expected.applying(individual(id)) }
            let batch = try source.applying(.editComponentWrapping(ids: ["d", "b", "a", "c"], edit: edit))
            XCTAssertEqual(try tree(batch), try tree(expected))
        }
        for property in ComponentWrappingScalarProperty.allCases {
            for value in [property.bounds.lowerBound, property.bounds.upperBound, property.defaultValue(for: .cloth)] {
                var expected = source
                for id in ["a", "b", "c", "d"] {
                    expected = try expected.applying(.setComponentWrapScalar(id: id, property: property, value: value))
                }
                XCTAssertEqual(
                    try tree(
                        source.applying(
                            .editComponentWrapping(ids: ["a", "b", "c", "d"], edit: .scalar(property, value)))),
                    try tree(expected))
            }
        }
        for property in ComponentSurfaceScalar.allCases {
            for value in [property.bounds.lowerBound, property.bounds.upperBound, property.defaultValue] {
                var expected = source
                for id in ["a", "b", "c", "d"] {
                    expected = try expected.applying(
                        .setComponentSurfaceScalar(id: id, property: property, value: value))
                }
                XCTAssertEqual(
                    try tree(
                        source.applying(
                            .editComponentWrapping(ids: ["a", "b", "c", "d"], edit: .surfaceScalar(property, value)))),
                    try tree(expected))
            }
        }
    }
    func testInvalidValuesAndLinkedOwnersRejectAtomically() throws {
        let source = try document()
        for edit in [
            ComponentWrappingEdit.scalar(.offset, .nan), .scalar(.drape, 2), .targetFaces(63), .targetFaces(20001),
            .surfaceScalar(.wrinkles, .infinity), .surfaceInk(.init(red: 1, green: 2, blue: 3, alpha: 4)),
        ] {
            XCTAssertThrowsError(try source.applying(.editComponentWrapping(ids: ["a", "b"], edit: edit)))
        }
        let linked = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes/><edges/><parts><part id='p' locked='true' visible='false' disabled='true'/></parts><components><component id='a' wrap='Cloth'/><component id='linked' linkDataType='partId' linkData='p'/><component id='opaque' linkDataType='future' linkData='body'/></components></canvas>"
                    .utf8))
        for id in ["linked", "opaque"] {
            XCTAssertThrowsError(try linked.applying(.editComponentWrapping(ids: ["a", id], edit: .mode(.skin))))
        }
        XCTAssertEqual(
            try linked.applying(.editComponentWrapping(ids: ["a"], edit: .mode(.skin))).editorContents().parts,
            try linked.editorContents().parts)
    }
    func testNoopPreservesArchiveRedoAndFinishIdentityClassification() throws {
        let source = try document()
        XCTAssertEqual(
            try source.applying(.editComponentWrapping(ids: ["a"], edit: .mode(.skin))).encoded(), source.encoded())
        var history = DocumentHistory(document: source)
        let initial = history.previewIdentity
        try history.apply(.editComponentWrapping(ids: ["a", "b"], edit: .surfacePattern(.spots)))
        XCTAssertEqual(history.previewIdentity.geometry, initial.geometry)
        XCTAssertNotEqual(history.previewIdentity.materials, initial.materials)
        history.undo()
        XCTAssertEqual(history.document.encoded(), source.encoded())
        try history.apply(.editComponentWrapping(ids: ["a"], edit: .mode(.skin)))
        XCTAssertTrue(history.canRedo)
        history.redo()
        let before = history.previewIdentity
        try history.apply(.editComponentWrapping(ids: ["a", "b"], edit: .scalar(.offset, 0.1)))
        XCTAssertNotEqual(history.previewIdentity.geometry, before.geometry)
        XCTAssertNotEqual(history.previewIdentity.materials, before.materials)
    }

    func testPureExportTwoGarmentBatchCandidateWithoutNativeExecution() throws {
        let source = try XCTUnwrap(
            Data(
                base64Encoded:
                    "RFVTVDNEIDEuMCB4bWwgMDAwMDAwMDA4Ng0KPGRzMz48bW9kZWwgbmFtZT0ibW9kZWwueG1sIiBvZmZzZXQ9IjAiIHNpemU9IjEwMDUiLz48L2RzMz48Y2FudmFzIG9yaWdpblg9Jy41JyBvcmlnaW5ZPScuNScgb3JpZ2luWj0nLjUnPjxub2Rlcz48bm9kZSBpZD0nezAwMDAxMDAxLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMTAwMX0nIHBhcnRJZD0nezAwMDAwMTAxLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDEwMX0nIHg9Jy4yNScgeT0nLjUnIHo9Jy41JyByYWRpdXM9Jy4xNScvPjxub2RlIGlkPSd7MDAwMDEwMDItMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAxMDAyfScgcGFydElkPSd7MDAwMDAxMDItMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMTAyfScgeD0nLjc1JyB5PScuNScgej0nLjUnIHJhZGl1cz0nLjE1Jy8+PC9ub2Rlcz48ZWRnZXMvPjxwYXJ0cz48cGFydCBpZD0nezAwMDAwMTAxLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDEwMX0nLz48cGFydCBpZD0nezAwMDAwMTAyLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDEwMn0nLz48L3BhcnRzPjxjb21wb25lbnRzPjxjb21wb25lbnQgaWQ9J3swMDAwMDMwMS0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAzMDF9JyB3cmFwPSdDbG90aCcgd3JhcEZhY2VzPSc2NCcgd3JhcEtlZXA9J2ZhbHNlJyB3cmFwT2Zmc2V0PScuMDEyJz48Y29tcG9uZW50IGlkPSd7MDAwMDAyMDEtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMjAxfScgbGlua0RhdGFUeXBlPSdwYXJ0SWQnIGxpbmtEYXRhPSd7MDAwMDAxMDEtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMTAxfScvPjwvY29tcG9uZW50Pjxjb21wb25lbnQgaWQ9J3swMDAwMDMwMi0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAzMDJ9JyB3cmFwPSdDbG90aCcgd3JhcEZhY2VzPSc2NCcgd3JhcEtlZXA9J2ZhbHNlJyB3cmFwT2Zmc2V0PScuMDEyJz48Y29tcG9uZW50IGlkPSd7MDAwMDAyMDItMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMjAyfScgbGlua0RhdGFUeXBlPSdwYXJ0SWQnIGxpbmtEYXRhPSd7MDAwMDAxMDItMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMTAyfScvPjwvY29tcG9uZW50PjwvY29tcG9uZW50cz48L2NhbnZhcz4="
            ))
        let document = try Dust3DDocument(data: source)
        let changed = try document.applying(
            .editComponentWrapping(
                ids: ["{00000301-0000-4000-8000-000000000301}", "{00000302-0000-4000-8000-000000000302}"],
                edit: .scalar(.offset, 0.025)))
        XCTAssertTrue(
            try changed.components().filter(\.isGroup).allSatisfy { $0.wrapping.scalarValue(.offset) == 0.025 })
        XCTAssertEqual(try changed.editorContents().nodes, try document.editorContents().nodes)
        if let directory = ProcessInfo.processInfo.environment["DUST3D_UI_QA_OUTPUT_DIR"] {
            try changed.encoded().write(
                to: URL(fileURLWithPath: directory).appendingPathComponent("two-garment-mutated.ds3"))
            try changed.modelXML.write(
                to: URL(fileURLWithPath: directory).appendingPathComponent("two-garment-mutated.xml"))
        }
    }

    func testBatchWrappingRejectsDanglingLiteralAliasWithoutHistoryChanges() throws {
        let source = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas><nodes/><edges/><parts/><components><component id='cafe&#769;' wrap='Cloth'/><component id='other' wrap='Skin'/></components></canvas>"
                    .utf8))
        for edit: ComponentWrappingEdit in [
            .mode(.skin), .scalar(.drape, 0.3), .keepChildren(false), .targetFaces(500), .surfacePattern(.spots),
            .surfaceScalar(.wrinkles, 0.5), .surfaceInk(.init(red: 1, green: 2, blue: 3)),
        ] {
            var history = DocumentHistory(document: source)
            XCTAssertThrowsError(try history.apply(.editComponentWrapping(ids: ["other", "caf\u{e9}"], edit: edit)))
            XCTAssertEqual(history.document.encoded(), source.encoded())
            XCTAssertFalse(history.canUndo)
        }
    }

}
