import AppKit
import Observation
import SwiftUI
import XCTest

@testable import Dust3DEditor

@MainActor @Observable private final class InspectorVisibilityFixture {
    var isPresented: Bool
    init(_ value: Bool) { isPresented = value }
}

@MainActor private final class InspectorFixtureWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
final class InspectorVisibilityRenderingTests: XCTestCase {
    func testToolbarExposesChangingVisibilityIndependentlyInTwoOwnedWindows() async throws {
        _ = NSApplication.shared
        XCTAssertFalse(NSApplication.shared.isActive)
        let first = InspectorVisibilityFixture(true)
        let second = InspectorVisibilityFixture(false)
        func window(_ state: InspectorVisibilityFixture) -> NSWindow {
            let host = NSHostingView(
                rootView: EditorInspectorVisibilityControl(
                    isPresented: Binding(get: { state.isPresented }, set: { state.isPresented = $0 })
                ).padding(12))
            host.frame = NSRect(x: 0, y: 0, width: 320, height: 80)
            let window = InspectorFixtureWindow(
                contentRect: NSRect(x: -10000, y: -10000, width: 320, height: 80),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.contentView = host
            window.setContentSize(NSSize(width: 320, height: 80))
            window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
            window.orderBack(nil)
            return window
        }
        let calibration = window(InspectorVisibilityFixture(true))
        calibration.contentView = NSHostingView(
            rootView: Toggle("Inspector", isOn: .constant(true)).toggleStyle(.button).padding(12))
        calibration.contentView?.frame = NSRect(x: 0, y: 0, width: 320, height: 80)
        defer { calibration.close() }
        for _ in 0..<100 where !values(calibration).contains(1) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertLessThan(calibration.frame.maxX, -9000)
        XCTAssertFalse(calibration.isKeyWindow)
        XCTAssertFalse(NSApplication.shared.isActive)
        guard values(calibration).contains(1) else {
            throw XCTSkip(
                "Offscreen host does not expose the unmodified SwiftUI toggle's AX value; physical VoiceOver acceptance remains required"
            )
        }
        let firstWindow = window(first)
        let secondWindow = window(second)
        defer {
            firstWindow.close()
            secondWindow.close()
        }
        func wait(_ window: NSWindow, for expected: Int) async throws {
            for _ in 0..<100 where !values(window).contains(expected) {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        try await wait(firstWindow, for: 1)
        try await wait(secondWindow, for: 0)
        XCTAssertLessThan(firstWindow.frame.maxX, -9000)
        XCTAssertLessThan(secondWindow.frame.maxX, -9000)
        XCTAssertFalse(NSApplication.shared.isActive)
        XCTAssertFalse(firstWindow.isKeyWindow)
        XCTAssertFalse(secondWindow.isKeyWindow)
        XCTAssertTrue(values(firstWindow).contains(1), "Shown inspector must expose its active state")
        XCTAssertTrue(values(secondWindow).contains(0), "Hidden inspector must expose its inactive state")
        first.isPresented = false
        try await wait(firstWindow, for: 0)
        XCTAssertTrue(values(firstWindow).contains(0))
        XCTAssertTrue(values(secondWindow).contains(0))
        second.isPresented = true
        try await wait(secondWindow, for: 1)
        XCTAssertTrue(values(secondWindow).contains(1))
        XCTAssertTrue(values(firstWindow).contains(0), "Other window remains hidden")
    }

    func testVisibilityControlsRenderBothStatesInLightAndDark() throws {
        for scheme in [ColorScheme.light, .dark] {
            let view = VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Shown")
                    EditorInspectorVisibilityControl(isPresented: .constant(true))
                }
                HStack {
                    Text("Hidden")
                    EditorInspectorVisibilityControl(isPresented: .constant(false))
                }
            }
            let png = try InspectorRenderer.png(view, width: 320, scheme: scheme)
            XCTAssertGreaterThan(png.count, 100)
            if let path = ProcessInfo.processInfo.environment["DUST3D_UI_QA_OUTPUT_DIR"] {
                let destination = URL(fileURLWithPath: path, isDirectory: true)
                    .appendingPathComponent("inspector-visibility-" + (scheme == .dark ? "dark" : "light") + ".png")
                try png.write(to: destination, options: .atomic)
            }
        }
    }

    private func values(_ window: NSWindow) -> [Int] {
        window.contentView?.layoutSubtreeIfNeeded()
        var visited = Set<ObjectIdentifier>()
        // SwiftUI virtual AX nodes may implement the public getters without
        // declaring NSAccessibilityProtocol conformance. Do not discard them.
        func attribute(_ object: NSObject, getter: String, legacy: String) -> AnyObject? {
            var typed: AnyObject?
            if let element = object as? NSAccessibilityProtocol {
                switch getter {
                case "accessibilityLabel": typed = element.accessibilityLabel() as AnyObject?
                case "accessibilityTitle": typed = element.accessibilityTitle() as AnyObject?
                case "accessibilityIdentifier": typed = element.accessibilityIdentifier() as AnyObject?
                case "accessibilityValue": typed = element.accessibilityValue() as AnyObject?
                case "accessibilityChildren": typed = element.accessibilityChildren() as AnyObject?
                default: break
                }
            }
            if let typed { return typed }
            let selector = NSSelectorFromString(getter)
            if object.responds(to: selector), let value = object.perform(selector)?.takeUnretainedValue() {
                return value
            }
            let fallback = NSSelectorFromString("accessibilityAttributeValue:")
            guard object.responds(to: fallback) else { return nil }
            return object.perform(fallback, with: legacy as NSString)?.takeUnretainedValue()
        }
        func visit(_ raw: Any) -> [Int] {
            guard let object = raw as? NSObject, visited.count < 256,
                visited.insert(ObjectIdentifier(object)).inserted
            else { return [] }
            let names = [
                attribute(object, getter: "accessibilityLabel", legacy: "AXDescription") as? String,
                attribute(object, getter: "accessibilityTitle", legacy: "AXTitle") as? String,
            ].compactMap { $0 }
            let identifier = attribute(object, getter: "accessibilityIdentifier", legacy: "AXIdentifier") as? String
            var result: [Int] = []
            if names.contains("Inspector") || identifier == "editor.inspector.visibility" {
                let value = attribute(object, getter: "accessibilityValue", legacy: "AXValue")
                if let number = value as? NSNumber {
                    result.append(number.intValue)
                } else if let text = value as? String, let number = Int(text) {
                    result.append(number)
                }
            }
            let children =
                (attribute(object, getter: "accessibilityChildren", legacy: "AXChildren") as? [Any] ?? [])
                + ((object as? NSView)?.subviews ?? [])
            return result + children.flatMap(visit)
        }
        return visit(window)
    }
}
