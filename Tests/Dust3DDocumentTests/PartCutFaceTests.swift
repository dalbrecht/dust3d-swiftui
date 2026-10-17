import Dust3DDocument
import Foundation
import XCTest

final class PartCutFaceTests: XCTestCase {
    private let owner = "{aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}"
    private let profile = "{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}"
    private func document(
        _ attributes: String = "", profileAttributes: String = "", profileNodeAttributes: String = "",
        profileID: String? = nil, extraParts: String = ""
    ) throws -> Dust3DDocument {
        let profileID = profileID ?? profile
        let model = Data(
            "<canvas><nodes><node id='n' partId='\(owner)' x='.5' y='.5' z='.5' radius='.1' cutFace='future'/><node id='p' partId='\(profileID)' x='.7' y='.5' z='.5' radius='.1' \(profileNodeAttributes)/></nodes><edges/><parts><part id='\(owner)' future='keep' locked='true' disabled='true' visible='false' \(attributes)/><part id='\(profileID)' target='CutFace' \(profileAttributes)/><part id='legacy'/>\(extraParts)</parts><components><component id='c' linkDataType='partId' linkData='\(owner)'/></components></canvas>"
                .utf8)
        let header =
            "<ds3><model name='model.xml' offset='0' size='\(model.count)'/><asset name='opaque.bin' offset='\(model.count)' size='4'/></ds3>"
        let prefix = "DUST3D 1.0 xml "
        return try Dust3DDocument(
            data: Data((prefix + String(format: "%010d\r\n", prefix.utf8.count + 12 + header.utf8.count) + header).utf8)
                + model + Data([0, 255, 10, 128]))
    }
    func testDefaultsPresetsUnknownValuesAndExactLinkedIdentitiesRemainLossless() throws {
        let baseline = try document()
        XCTAssertEqual(try baseline.editorContents().parts.first?.cutFace, .preset(.quad))
        XCTAssertEqual(try baseline.editorContents().parts.first?.cutRotation, 0)
        for preset in CutFacePreset.allCases {
            XCTAssertEqual(
                try document("cutFace='\(preset.rawValue)'").editorContents().parts.first?.cutFace, .preset(preset))
        }
        for text in ["", "future", "UserDefined", profile, String(profile.dropFirst().dropLast())] {
            let source = try document("cutFace='\(text)'")
            let expected: CutFaceSelection? =
                text.isEmpty ? .preset(.quad) : (text.count > 30 ? .linkedPart(text) : nil)
            XCTAssertEqual(try source.editorContents().parts.first?.cutFace, expected)
            XCTAssertEqual(try Dust3DDocument(data: source.encoded()).encoded(), source.encoded())
        }
        for text in [
            "", "0", "-1", "1", "0.005", "-0.005", "future", "nan", "inf", "1.01", "-1.01", "5e-324", "1e-999",
        ] {
            let value = try document("cutRotation='\(text)'").editorContents().parts.first?.cutRotation
            if ["", "0"].contains(text) {
                XCTAssertEqual(value, 0)
            } else if ["-1", "1", "0.005", "-0.005"].contains(text) {
                XCTAssertEqual(value, Double(text))
            } else {
                XCTAssertNil(value, text)
            }
        }
    }
    func testPresetAndLinkedEditsPreserveNodesFlagsAssetsAndExactHistory() throws {
        for selection in CutFacePreset.allCases.map({ CutFaceSelection.preset($0) }) + [.linkedPart(profile)] {
            let source = try document("cutFace='future' cutRotation='0.005'")
            var history = DocumentHistory(document: source)
            try history.apply(.setPartCutFace(id: owner, selection: selection))
            let changed = history.document
            let part = try XCTUnwrap(changed.editorContents().parts.first)
            XCTAssertEqual(part.cutFace, selection)
            XCTAssertEqual(part.cutRotation, 0.005)
            XCTAssertTrue(part.isLocked)
            XCTAssertTrue(part.isDisabled)
            XCTAssertFalse(part.isVisible)
            XCTAssertEqual(try changed.editorContents().nodes, try source.editorContents().nodes)
            XCTAssertEqual(changed.asset(named: "opaque.bin"), source.asset(named: "opaque.bin"))
            XCTAssertEqual(
                try Dust3DDocument(data: changed.encoded()).editorContents().parts, try changed.editorContents().parts)
            let xml = try XMLDocument(data: changed.modelXML)
            XCTAssertEqual(
                (try xml.nodes(forXPath: "//part").first as? XMLElement)?.attribute(forName: "future")?.stringValue,
                "keep")
            XCTAssertTrue(history.undo())
            XCTAssertEqual(history.document.encoded(), source.encoded())
            XCTAssertTrue(history.redo())
            XCTAssertEqual(history.document.encoded(), changed.encoded())
        }
        let rawID = String(profile.dropFirst().dropLast())
        let source = try document(profileID: rawID)
        let changed = try source.applying(.setPartCutFace(id: owner, selection: .linkedPart(rawID)))
        XCTAssertEqual(try changed.editorContents().parts.first?.cutFace, .linkedPart(rawID))
    }
    func testRotationBoundariesAndFineValuesKeepExactUndoRedoAndUnrelatedMetadata() throws {
        for rotation in [-1.0, -0.005, 0, 0.005, 1] {
            let source = try document("cutRotation='future' cutFace='Triangle'")
            var history = DocumentHistory(document: source)
            try history.apply(.setPartCutRotation(id: owner, rotation: rotation))
            let changed = history.document
            XCTAssertEqual(try changed.editorContents().parts.first?.cutRotation, rotation)
            XCTAssertEqual(try changed.editorContents().parts.first?.cutFace, .preset(.triangle))
            XCTAssertEqual(changed.asset(named: "opaque.bin"), source.asset(named: "opaque.bin"))
            XCTAssertEqual(try changed.editorContents().nodes, try source.editorContents().nodes)
            let xml = try XMLDocument(data: changed.modelXML)
            let attribute = (try xml.nodes(forXPath: "//part").first as? XMLElement)?.attribute(forName: "cutRotation")
            XCTAssertEqual(attribute == nil, rotation == 0)
            XCTAssertEqual(
                try Dust3DDocument(data: changed.encoded()).editorContents().parts, try changed.editorContents().parts)
            XCTAssertTrue(history.undo())
            XCTAssertEqual(history.document.encoded(), source.encoded())
            XCTAssertTrue(history.redo())
            XCTAssertEqual(history.document.encoded(), changed.encoded())
        }
    }
    func testSemanticNoOpsPreserveOriginalSpellingsBytesAndRedo() throws {
        let source = try document("cutFace='Quad' cutRotation='1e0'")
        for pair in [
            (
                DocumentCommand.setPartCutFace(id: owner, selection: .preset(.triangle)),
                DocumentCommand.setPartCutFace(id: owner, selection: .preset(.quad))
            ),
            (.setPartCutRotation(id: owner, rotation: 0.5), .setPartCutRotation(id: owner, rotation: 1)),
        ] {
            var history = DocumentHistory(document: source)
            try history.apply(pair.0)
            let changed = history.document.encoded()
            XCTAssertTrue(history.undo())
            try history.apply(pair.1)
            XCTAssertEqual(history.document.encoded(), source.encoded())
            XCTAssertTrue(history.redo())
            XCTAssertEqual(history.document.encoded(), changed)
        }
    }
    func testInvalidRotationsAndProfileIdentitiesRejectWithoutChangingSource() throws {
        let source = try document()
        for rotation in [-1.001, 1.001, Double.nan, .infinity, -.infinity, Double.leastNonzeroMagnitude] {
            XCTAssertThrowsError(try source.applying(.setPartCutRotation(id: owner, rotation: rotation))) {
                XCTAssertEqual($0 as? DocumentError, .invalidPartCutRotation)
            }
        }
        XCTAssertThrowsError(try source.applying(.setPartCutFace(id: owner, selection: .linkedPart("legacy")))) {
            XCTAssertEqual($0 as? DocumentError, .invalidPartCutFace)
        }
        let missing = "{dddddddd-dddd-4ddd-8ddd-dddddddddddd}"
        XCTAssertThrowsError(try source.applying(.setPartCutFace(id: owner, selection: .linkedPart(missing)))) {
            XCTAssertEqual($0 as? DocumentError, .missingPart(missing))
        }
        for command in [
            DocumentCommand.setPartCutFace(id: "missing", selection: .preset(.quad)),
            .setPartCutRotation(id: "missing", rotation: 0.5),
        ] {
            XCTAssertThrowsError(try source.applying(command)) {
                XCTAssertEqual($0 as? DocumentError, .missingPart("missing"))
            }
        }
    }
    func testUnrelatedImportedCyclesDoNotBlockPresetOrIndependentLinkedEdits() throws {
        let first = "{dddddddd-dddd-4ddd-8ddd-dddddddddddd}"
        let second = "{eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee}"
        let cycle = "<part id='\(first)' cutFace='\(second)'/><part id='\(second)' cutFace='\(first)'/>"
        for source in [
            try document(extraParts: cycle), try document(profileAttributes: "cutFace='\(first)'", extraParts: cycle),
        ] {
            for selection in [CutFaceSelection.preset(.triangle), .linkedPart(profile)] {
                var history = DocumentHistory(document: source)
                try history.apply(.setPartCutFace(id: owner, selection: selection))
                let changed = history.document
                XCTAssertEqual(try changed.editorContents().parts.first?.cutFace, selection)
                XCTAssertEqual(changed.asset(named: "opaque.bin"), source.asset(named: "opaque.bin"))
                let xml = try XMLDocument(data: changed.modelXML)
                XCTAssertEqual(
                    (try xml.nodes(forXPath: "//part[@id='\(first)']").first as? XMLElement)?.attribute(
                        forName: "cutFace")?
                        .stringValue, second)
                XCTAssertEqual(
                    (try xml.nodes(forXPath: "//part[@id='\(second)']").first as? XMLElement)?.attribute(
                        forName: "cutFace")?.stringValue, first)
                XCTAssertTrue(history.undo())
                XCTAssertEqual(history.document.encoded(), source.encoded())
                XCTAssertTrue(history.redo())
                XCTAssertEqual(history.document.encoded(), changed.encoded())
            }
        }
    }

    func testPartAndNodeProfileCyclesRejectAtomically() throws {
        let selfSource = try document()
        XCTAssertThrowsError(try selfSource.applying(.setPartCutFace(id: owner, selection: .linkedPart(owner)))) {
            XCTAssertEqual($0 as? DocumentError, .cyclicProfile)
        }
        for source in [
            try document(profileAttributes: "cutFace='\(owner)'"),
            try document(profileNodeAttributes: "cutFace='\(owner)'"),
        ] {
            let bytes = source.encoded()
            XCTAssertThrowsError(try source.applying(.setPartCutFace(id: owner, selection: .linkedPart(profile)))) {
                XCTAssertEqual($0 as? DocumentError, .cyclicProfile)
            }
            XCTAssertEqual(source.encoded(), bytes)
        }
    }
}
