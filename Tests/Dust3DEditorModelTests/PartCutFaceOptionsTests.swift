import Dust3DDocument
import Dust3DEditorModel
import XCTest

final class PartCutFaceOptionsTests: XCTestCase {
    func testSupportedPresetsOnlyOfferActionablePresetChoices() {
        let presets = CutFacePreset.allCases.map { Optional(CutFaceSelection.preset($0)) }
        for preset in CutFacePreset.allCases {
            let options = PartCutFaceOptions.selections(current: .preset(preset))
            XCTAssertEqual(options, presets)
            XCTAssertFalse(options.contains(nil))
        }
    }

    func testLinkedProfilesRetainExactCurrentChoiceWithoutAnUnsupportedAction() {
        for id in ["{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}", "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC"] {
            let current = CutFaceSelection.linkedPart(id)
            let options = PartCutFaceOptions.selections(current: current)
            XCTAssertEqual(options, CutFacePreset.allCases.map { Optional(CutFaceSelection.preset($0)) } + [current])
            XCTAssertFalse(options.contains(nil))
            XCTAssertEqual(Set(options).count, options.count)
        }
    }

    func testUnsupportedSourceRetainsPlaceholderAlongsideExplicitReplacements() {
        let options = PartCutFaceOptions.selections(current: nil)
        XCTAssertEqual(options, [nil] + CutFacePreset.allCases.map { Optional(CutFaceSelection.preset($0)) })
        XCTAssertEqual(options.filter { $0 == nil }.count, 1)
    }
}
