import XCTest

@testable import Dust3DEditor

@MainActor
private final class RestMenuRecords {
    var current = true
    var mode = GeneratedRigPreviewSession.Presentation.model
    var model = true
    var bones = true
    var weights = true
    var writes: [String] = []
    var canReveal = true
    var reveals = 0

    func actions() -> EditorRestPreviewActions {
        EditorRestPreviewActions(
            isCurrent: { self.current }, mode: { self.mode },
            setMode: {
                self.mode = $0
                self.writes.append("mode")
            },
            showsModel: { self.model },
            setShowsModel: {
                self.model = $0
                self.writes.append("model")
            },
            showsBones: { self.bones },
            setShowsBones: {
                self.bones = $0
                self.writes.append("bones")
            },
            showsWeights: { self.weights },
            setShowsWeights: {
                self.weights = $0
                self.writes.append("weights")
            },
            canRevealSelectedJoint: { self.canReveal },
            revealSelectedJoint: { self.reveals += 1 })
    }
}

@MainActor
final class EditorRestPreviewActionsTests: XCTestCase {
    func testModeCommandsRemainAvailableInModelButVisibilityDoesNot() {
        let records = RestMenuRecords()
        let actions = records.actions()
        XCTAssertTrue(actions.canChangeMode)
        XCTAssertEqual(actions.mode, .model)
        XCTAssertFalse(actions.canChangeVisibility)
        XCTAssertFalse(actions.showsModel)
        XCTAssertFalse(actions.showsBones)
        XCTAssertFalse(actions.showsWeights)
        actions.setShowsModel(false)
        actions.setShowsBones(false)
        actions.setShowsWeights(false)
        XCTAssertTrue(records.writes.isEmpty)
        actions.setMode(.generatedRest)
        XCTAssertEqual(records.mode, .generatedRest)
        XCTAssertEqual(records.writes, ["mode"])
    }

    func testRestVisibilityCommandsReadAndWriteAllThreePreferences() {
        let records = RestMenuRecords()
        records.mode = .generatedRest
        let actions = records.actions()
        XCTAssertTrue(actions.canChangeVisibility)
        XCTAssertTrue(actions.showsModel)
        XCTAssertTrue(actions.showsBones)
        XCTAssertTrue(actions.showsWeights)
        actions.setShowsModel(false)
        actions.setShowsBones(false)
        actions.setShowsWeights(false)
        XCTAssertFalse(actions.showsModel)
        XCTAssertFalse(actions.showsBones)
        XCTAssertFalse(actions.showsWeights)
        XCTAssertEqual(records.writes, ["model", "bones", "weights"])
    }

    func testInvalidatedCapturedActionsRejectEverySetter() {
        let records = RestMenuRecords()
        records.mode = .generatedRest
        let actions = records.actions()
        records.current = false
        XCTAssertFalse(actions.canChangeMode)
        XCTAssertFalse(actions.canChangeVisibility)
        XCTAssertEqual(actions.mode, .model)
        XCTAssertFalse(actions.showsModel)
        XCTAssertFalse(actions.showsBones)
        XCTAssertFalse(actions.showsWeights)
        actions.setMode(.model)
        actions.setShowsModel(false)
        actions.setShowsBones(false)
        actions.setShowsWeights(false)
        XCTAssertEqual(records.mode, .generatedRest)
        XCTAssertTrue(records.model && records.bones && records.weights)
        XCTAssertTrue(records.writes.isEmpty)
    }

    func testLeavingRestModeDisablesVisibilityWithoutClearingPreferences() {
        let records = RestMenuRecords()
        records.mode = .generatedRest
        let actions = records.actions()
        actions.setMode(.model)
        XCTAssertFalse(actions.canChangeVisibility)
        actions.setShowsModel(false)
        actions.setShowsBones(false)
        actions.setShowsWeights(false)
        XCTAssertTrue(records.model && records.bones && records.weights)
        XCTAssertEqual(records.writes, ["mode"])
    }
    func testRevealChecksCurrentRestModeAndCurrentJointAvailabilityAtDispatch() {
        let records = RestMenuRecords()
        let actions = records.actions()
        XCTAssertFalse(actions.canRevealSelectedJoint)
        actions.revealSelectedJoint()
        XCTAssertEqual(records.reveals, 0)
        records.mode = .generatedRest
        XCTAssertTrue(actions.canRevealSelectedJoint)
        actions.revealSelectedJoint()
        XCTAssertEqual(records.reveals, 1)
        records.canReveal = false
        XCTAssertFalse(actions.canRevealSelectedJoint)
        actions.revealSelectedJoint()
        records.canReveal = true
        records.current = false
        XCTAssertFalse(actions.canRevealSelectedJoint)
        actions.revealSelectedJoint()
        XCTAssertEqual(records.reveals, 1)
        XCTAssertTrue(records.writes.isEmpty)
    }

}
