import AppKit
import Dust3DEditorModel
import Dust3DRendering
import OSLog
import SwiftUI

struct Dust3DEditorApp: App {
    @Environment(\.openWindow) private var openWindow
    private let buildIdentity = RuntimeBuildIdentity.current
    @NSApplicationDelegateAdaptor(EditorAppDelegate.self) private var appDelegate
    @FocusedValue(\.editorStore) private var store
    @State private var pasteboard = EditorPasteboard()

    private var applicationName: String {
        BuildIdentityPresentation.applicationName(
            bundleIdentifier: buildIdentity.launchBundleIdentifier, fallback: "Dust3D Editor")
    }

    var body: some Scene {
        DocumentGroup(newDocument: EditorFileDocument()) { file in
            EditorRootView(file: file.$document)
                .environment(pasteboard)
                .id(file.document.identity)
        }
        .defaultSize(width: 1300, height: 820)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About \(applicationName)…") { openWindow(id: "build-diagnostics") }
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { store?.undo() }
                    .keyboardShortcut("z")
                    .disabled(store?.canUndo != true)
                Button("Redo") { store?.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(store?.canRedo != true)
            }
            EditorClipboardCommands(pasteboard: pasteboard)
            CommandMenu("Canvas") {
                Toggle(
                    "Move Origin",
                    isOn: Binding(get: { store?.isMovingOrigin == true }, set: { store?.setMovingOrigin($0) })
                )
                .disabled(store?.isWorking != false || store?.snapshot?.origin == nil)
                Button("Center Origin on Model") { store?.centerOriginOnModel() }
                    .disabled(store?.snapshot == nil || store?.isWorking != false)
                Button("Cancel Origin Move") { store?.cancelOriginDrag() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .disabled(store?.isMovingOrigin != true)
                Divider()
                Button("Select All Nodes") { store?.selectAll() }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(store?.snapshot == nil || store?.isWorking != false)
                Button("Clear Selection") { store?.select(nil) }
                    .disabled(store?.snapshot == nil || store?.isWorking != false)
                Menu("Transform Selected Nodes") {
                    ForEach(SelectionTransform.allCases, id: \.self) { transform in
                        Button(transform.rawValue) { store?.transformSelection(transform) }
                            .disabled(transform.usesOrigin && store?.snapshot?.origin == nil)
                    }
                }
                .disabled(store?.canTransform != true)
                DescendantRotationMenu(store: store)
                Button("Reverse Edges Between Selected Nodes") { store?.reverseSelectedEdges() }
                    .disabled(store?.isWorking != false || store?.snapshot?.reversibleEdges.isEmpty != false)
                Button("Reverse Selected Edge") {
                    if let id = store?.snapshot?.selectedEdgeID { store?.reverseEdge(id) }
                }
                .disabled(store?.isWorking != false || store?.snapshot?.canEditSelectedEdge != true)
                Button("Delete Selected Edge") { store?.deleteSelection() }
                    .keyboardShortcut(.delete, modifiers: [])
                    .disabled(store?.isWorking != false || store?.snapshot?.canEditSelectedEdge != true)
                Divider()
                ForEach(EditingConstraint.allCases, id: \.self) { constraint in
                    Toggle(
                        "Lock \(constraint.rawValue)",
                        isOn: Binding(
                            get: { store?.locks.contains(constraint) == true },
                            set: { store?.setLock(constraint, isLocked: $0) })
                    )
                    .keyboardShortcut(shortcut(for: constraint), modifiers: [.command, .option])
                    .disabled(store?.snapshot == nil || store?.isWorking != false)
                }
            }
        }
        Window("About \(applicationName)", id: "build-diagnostics") {
            BuildDiagnosticsView(applicationName: applicationName, identity: buildIdentity)
        }
        .defaultSize(width: 660, height: 520)
    }

    private func shortcut(for constraint: EditingConstraint) -> KeyEquivalent {
        switch constraint {
        case .x: "x"
        case .y: "y"
        case .z: "z"
        case .radius: "r"
        }
    }
}

@MainActor
final class EditorAppDelegate: NSObject, NSApplicationDelegate {
    private let buildIdentity = RuntimeBuildIdentity.current
    private let launchDocument = EditorLaunchDocumentOpener(arguments: CommandLine.arguments)
    private let recoveryRequestGate = EditorRecoveryRequestGate()

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        !launchDocument.shouldSuppressUntitledDocument
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildIdentity.logStartup(fallbackSubsystem: "org.dust3d.editor")
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(cancelReferenceComposition(_:)),
            name: EditorCompositionRecovery.notification, object: Bundle.main.bundleIdentifier)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(writeRecoveryCopies(_:)),
            name: EditorRecoveryCopyChannel.notification, object: Bundle.main.bundleIdentifier)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            await launchDocument.openRequestedDocument(
                open: { url in
                    _ = try await NSDocumentController.shared.openDocument(withContentsOf: url, display: true)
                },
                reportError: { error in NSApp.presentError(error) })
        }
    }

    @objc nonisolated private func writeRecoveryCopies(_ notification: Notification) {
        guard
            let requestID = EditorRecoveryCopyChannel.requestID(
                notification, bundleIdentifier: Bundle.main.bundleIdentifier)
        else { return }
        let logger = Logger(subsystem: "org.dust3d.editor", category: "recovery")
        guard recoveryRequestGate.begin() else {
            logger.error(
                "operation=recoveryCopies requestID=\(requestID.uuidString, privacy: .public) cause=alreadyWriting")
            return
        }
        Task { @MainActor in
            defer { recoveryRequestGate.finish() }
            do {
                let report = try await EditorRecoveryCopyRegistry.shared.recover(requestID: requestID)
                logger.info(
                    "operation=recoveryCopies requestID=\(requestID.uuidString, privacy: .public) copied=\(report.copied.count) failed=\(report.failures.count)"
                )
                for failure in report.failures {
                    logger.error(
                        "operation=recoveryCopy requestID=\(requestID.uuidString, privacy: .public) cause=\(String(describing: failure.cause), privacy: .private)"
                    )
                }
                if let cause = report.receiptError {
                    logger.error(
                        "operation=recoveryReceipt requestID=\(requestID.uuidString, privacy: .public) cause=\(String(describing: cause), privacy: .private)"
                    )
                }
            } catch {
                logger.error(
                    "operation=recoveryCopies requestID=\(requestID.uuidString, privacy: .public) cause=\(String(describing: error), privacy: .private)"
                )
            }
        }
    }

    @objc nonisolated private func cancelReferenceComposition(_ notification: Notification) {
        Task { @MainActor in
            let cancelled = EditorCompositionRecovery.shared.cancelLatest()
            Logger(
                subsystem: RuntimeBuildIdentity.current.loggingSubsystem(fallback: "org.dust3d.editor"),
                category: "recovery"
            )
            .info("operation=cancelReferenceComposition cancelled=\(cancelled)")
        }
    }
}

private struct EditorTextEditingKey: FocusedValueKey { typealias Value = Bool }

private struct EditorStoreKey: FocusedValueKey { typealias Value = EditorStore }

extension FocusedValues {
    var editorTextEditing: Bool? {
        get { self[EditorTextEditingKey.self] }
        set { self[EditorTextEditingKey.self] = newValue }
    }

    var editorStore: EditorStore? {
        get { self[EditorStoreKey.self] }
        set { self[EditorStoreKey.self] = newValue }
    }
}
