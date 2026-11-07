import Dust3DEditorModel
import XCTest

@testable import Dust3DEditor

@MainActor final class CanvasPointerActivityTests: XCTestCase {
    func testSecondaryCancellationClearsVisibleMarqueeHoverAndInteractionGate() {
        var activity = CanvasPointerActivity(hasMarquee: true, hasHover: true)
        var visible: CanvasSelectionRectangle? = .init(from: .init(x: 1, y: 2), to: .init(x: 10, y: 20))
        var hover: CanvasPoint? = .init(x: 10, y: 20)
        var interactionActive = true
        let cancellation = activity.clear()
        XCTAssertFalse(activity.hasMarquee)
        XCTAssertFalse(activity.hasHover)
        cancellation.notify(
            rectangle: {
                visible = $0
                interactionActive = $0 != nil
            }, hover: { hover = $0 })
        XCTAssertNil(visible)
        XCTAssertNil(hover)
        XCTAssertFalse(interactionActive)
    }
    func testCancellationOnlyNotifiesPresentationThatWasActive() {
        var activity = CanvasPointerActivity(hasMarquee: true, hasHover: false)
        var rectangleCalls = 0
        var hoverCalls = 0
        activity.clear().notify(
            rectangle: {
                XCTAssertNil($0)
                rectangleCalls += 1
            }, hover: { _ in hoverCalls += 1 })
        activity.clear().notify(rectangle: { _ in rectangleCalls += 1 }, hover: { _ in hoverCalls += 1 })
        XCTAssertEqual(rectangleCalls, 1)
        XCTAssertEqual(hoverCalls, 0)
        activity.hasHover = true
        activity.clear().notify(
            rectangle: { _ in rectangleCalls += 1 },
            hover: {
                XCTAssertNil($0)
                hoverCalls += 1
            })
        XCTAssertEqual(rectangleCalls, 1)
        XCTAssertEqual(hoverCalls, 1)
    }
    func testSilentLifecycleResetDoesNotNotifyUnrelatedPresentation() {
        var activity = CanvasPointerActivity(hasMarquee: true, hasHover: true)
        activity = CanvasPointerActivity()
        var notifications = 0
        activity.clear().notify(rectangle: { _ in notifications += 1 }, hover: { _ in notifications += 1 })
        XCTAssertEqual(notifications, 0)
    }
    func testNotificationCannotEraseANewerActivationStartedByItsCallback() {
        var activity = CanvasPointerActivity(hasMarquee: true, hasHover: true)
        let cancellation = activity.clear()
        cancellation.notify(rectangle: { _ in activity.hasMarquee = true }, hover: { _ in activity.hasHover = true })
        XCTAssertTrue(activity.hasMarquee)
        XCTAssertTrue(activity.hasHover)
        var notifications = 0
        activity.clear().notify(rectangle: { _ in notifications += 1 }, hover: { _ in notifications += 1 })
        XCTAssertEqual(notifications, 2)
    }
    func testPrimaryReleaseClearsMarqueeBeforeNotificationAndPreservesHover() {
        var activity = CanvasPointerActivity(hasMarquee: true, hasHover: true)
        let release = activity.finishMarquee()
        XCTAssertFalse(activity.hasMarquee)
        XCTAssertTrue(activity.hasHover)
        var hoverCalls = 0
        release.notify(
            rectangle: {
                XCTAssertNil($0)
                activity.hasMarquee = true
            }, hover: { _ in hoverCalls += 1 })
        XCTAssertTrue(activity.hasMarquee)
        XCTAssertTrue(activity.hasHover)
        XCTAssertEqual(hoverCalls, 0)
    }

}
