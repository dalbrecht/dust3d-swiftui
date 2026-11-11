import AppKit
import Dust3DDocument
import Dust3DEditorModel
import Foundation
import SwiftUI
import XCTest

@testable import Dust3DEditor

@MainActor final class SurfaceInkRenderingTests: XCTestCase {
    private func wells(in view: NSView) -> [NSColorWell] {
        (view as? NSColorWell).map { [$0] } ?? view.subviews.flatMap { wells(in: $0) }
    }
    private func invoke(_ well: NSColorWell, color: NSColor, target: AnyObject?, action: Selector?) throws {
        let action = try XCTUnwrap(action)
        well.color = color
        XCTAssertTrue(NSApplication.shared.sendAction(action, to: target, from: well))
    }
    func testActualHostedNativeInkWellUpdatesOnlyDraftAndObsoleteWellCannotUndoCancel() throws {
        let source = ComponentColorValue.value(DocumentColor(red: 12, green: 34, blue: 56))
        let draft = SurfaceInkDraft(source: source)
        var commits: [DocumentColor] = []
        let png = try InspectorRenderer.png(
            SurfaceInkControls(
                source: .uniform(source), draft: draft, canEdit: { true }, apply: { commits.append($0) }, automatic: {}),
            width: 290, scheme: .light,
            inspect: { host in
                let well = try XCTUnwrap(self.wells(in: host).first)
                let target = well.target
                let action = well.action
                try self.invoke(well, color: .red, target: target, action: action)
                XCTAssertEqual(draft.color.parsedColor, .init(red: 255, green: 0, blue: 0))
                XCTAssertTrue(commits.isEmpty)
                draft.cancel(source: source)
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
                host.layoutSubtreeIfNeeded()
                let current = try XCTUnwrap(self.wells(in: host).first)
                XCTAssertFalse(current === well, "Cancel replaces the native well session")
                try self.invoke(well, color: .blue, target: target, action: action)
                XCTAssertEqual(draft.color.parsedColor, .init(red: 12, green: 34, blue: 56))
                XCTAssertTrue(commits.isEmpty)
            })
        XCTAssertGreaterThan(png.count, 100)
    }
    func testInkControlsRenderSupportedAutomaticAndUnsupportedSourceInBothAppearances() throws {
        let sources: [(String, ComponentWrappingSelectionValue<ComponentColorValue>)] = [
            ("auto", .uniform(.unset)), ("rgb", .uniform(.value(.init(red: 120, green: 40, blue: 20)))),
            ("unsupported", .uniform(.unsupported("future-ink"))), ("mixed", .mixed),
        ]
        for (name, source) in sources {
            for scheme in [ColorScheme.light, .dark] {
                let png = try InspectorRenderer.png(
                    SurfaceInkControls(source: source, canEdit: { true }, apply: { _ in }, automatic: {}),
                    width: 290,
                    scheme: scheme)
                XCTAssertGreaterThan(png.count, 100)
                if let output = ProcessInfo.processInfo.environment["DUST3D_UI_QA_OUTPUT_DIR"] {
                    try png.write(
                        to: URL(fileURLWithPath: output).appendingPathComponent(
                            "surface-ink-\(name)-\(scheme == .dark ? "dark" : "light").png"))
                }
            }
        }
    }
}
