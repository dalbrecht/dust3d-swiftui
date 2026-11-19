import AppKit
import Dust3DDocument
import Dust3DEditorModel
import SwiftUI
import XCTest

@testable import Dust3DEditor

private enum PreviewAnnouncementFailure: LocalizedError {
    case loading
    var errorDescription: String? { "The animation preview could not be prepared." }
}

private actor PreviewAnnouncementLoader {
    private(set) var calls = 0
    private(set) var isWaiting = false
    private(set) var isFinished = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var isReleased = false

    func fail(afterRelease: Bool = false) async throws -> SuppliedAnimationClip {
        calls += 1
        if afterRelease && !isReleased {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                isWaiting = true
            }
        }
        isFinished = true
        throw PreviewAnnouncementFailure.loading
    }

    func release() {
        isReleased = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
final class AnimationPreviewErrorAnnouncementTests: XCTestCase {
    private final class Owner {
        var isCurrent = true
        var isActive = true
        var messages: [String] = []
    }

    func testMountedCurrentActivePreviewAnnouncesOneErrorAcrossUnrelatedRefresh() async throws {
        let owner = Owner()
        let loader = PreviewAnnouncementLoader()
        let view = try await playbackView(owner: owner, loader: loader)
        let (window, host) = mount(view)
        defer { window.close() }

        try await waitForVisibleError(in: host)
        for _ in 0..<100 where owner.messages.isEmpty {
            try await settle(host, iterations: 1)
        }
        XCTAssertEqual(owner.messages, [PreviewAnnouncementFailure.loading.localizedDescription])
        host.rootView = view
        try await settle(host)
        XCTAssertEqual(owner.messages, [PreviewAnnouncementFailure.loading.localizedDescription])
        let calls = await loader.calls
        XCTAssertEqual(calls, 1)
    }

    func testMountedInactiveErrorIsConsumedBeforeLaterActivation() async throws {
        let owner = Owner()
        owner.isActive = false
        let loader = PreviewAnnouncementLoader()
        let view = try await playbackView(owner: owner, loader: loader)
        let (window, host) = mount(view)
        defer { window.close() }

        try await waitForVisibleError(in: host)
        try await settle(host)
        XCTAssertTrue(owner.messages.isEmpty)
        owner.isActive = true
        host.rootView = view
        try await settle(host)
        XCTAssertTrue(owner.messages.isEmpty)
    }

    func testMountedRetiredSourceDoesNotAnnounceLateLoadFailure() async throws {
        let owner = Owner()
        let loader = PreviewAnnouncementLoader()
        let view = try await playbackView(owner: owner, loader: loader, afterRelease: true)
        let (window, host) = mount(view)
        defer {
            window.close()
            Task { await loader.release() }
        }

        for _ in 0..<100 {
            if await loader.isWaiting { break }
            try await settle(host, iterations: 1)
        }
        let isWaiting = await loader.isWaiting
        XCTAssertTrue(isWaiting)
        owner.isCurrent = false
        await loader.release()
        try await settle(host)
        let isFinished = await loader.isFinished
        XCTAssertTrue(isFinished)
        XCTAssertTrue(owner.messages.isEmpty)
        XCTAssertFalse(visibleStrings(in: host).contains(PreviewAnnouncementFailure.loading.localizedDescription))
    }

    private func playbackView(
        owner: Owner, loader: PreviewAnnouncementLoader, afterRelease: Bool = false
    ) async throws -> ExperimentalAnimationPlaybackView {
        let document = try Dust3DDocument(
            snapshotXML: Data(
                "<canvas rigType='Fish'><animations><animation id='idle' type='FishIdle'/></animations></canvas>".utf8))
        let snapshot = try await EditorSession().open(data: document.encoded())
        let animation = try XCTUnwrap(document.animations().first)
        let request = EditorStore.AnimationPlaybackRequest(
            fileIdentity: UUID(), rig: GeneratedRigPreviewRequest(snapshot: snapshot),
            animation: animation, queryID: UUID())
        return ExperimentalAnimationPlaybackView(
            request: request, isCurrent: { owner.isCurrent },
            loader: { _, _ in try await loader.fail(afterRelease: afterRelease) },
            onPreviewErrorAnnouncement: { owner.messages.append($0) },
            previewAnnouncementIsActive: { _ in owner.isActive })
    }

    private func mount(_ view: ExperimentalAnimationPlaybackView)
        -> (NSWindow, NSHostingView<ExperimentalAnimationPlaybackView>)
    {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 380, height: 320),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
        return (window, host)
    }

    private func waitForVisibleError(in host: NSView) async throws {
        for _ in 0..<100 {
            if visibleStrings(in: host).contains(PreviewAnnouncementFailure.loading.localizedDescription) { return }
            try await settle(host, iterations: 1)
        }
        XCTFail("The mounted playback view did not display the loader's failure.")
    }

    private func settle(_ host: NSView, iterations: Int = 10) async throws {
        for _ in 0..<iterations {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    // Inspect metadata in the test-owned hierarchy without invoking accessibility actions.
    private func visibleStrings(in host: NSView) -> [String] {
        var visited: Set<ObjectIdentifier> = []
        func visit(_ object: Any) -> [String] {
            guard let element = object as? any NSAccessibilityProtocol,
                visited.count < 512, visited.insert(ObjectIdentifier(element)).inserted
            else { return [] }
            let strings = [
                element.accessibilityLabel(), element.accessibilityTitle(), element.accessibilityValue() as? String,
            ].compactMap { $0 }
            let children = (element.accessibilityChildren() ?? []) + ((object as? NSView)?.subviews ?? [])
            return strings + children.flatMap(visit)
        }
        return visit(host)
    }
}
