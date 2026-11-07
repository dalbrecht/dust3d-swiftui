import AppKit
import Dust3DEditorModel
import Dust3DRendering
import OSLog
import SwiftUI

struct Dust3DEditorApp: App {
    @Environment(\.openWindow) private var openWindow
    private let buildIdentity = RuntimeBuildIdentity.current
    @NSApplicationDelegateAdaptor(EditorAppDelegate.self) private var appDelegate
    #if MOTE3D_EXPERIMENTAL_GENERATED_RIG
        @FocusedValue(\.editorRestPreviewActions) private var restPreviewActions
    #endif
    @FocusedValue(\.editorStore) private var store
    @FocusedValue(\.rigAssignmentCommand) private var rigAssignmentCommand
    @FocusedValue(\.editorPreviewCameraActions) private var previewCameraActions
    @FocusedValue(\.editorPreviewDisplayActions) private var previewDisplayActions
    @FocusedValue(\.editorAnimationFocus) private var isAnimationFocused
    @FocusedValue(\.editorTextEditing) private var isEditingText
    @FocusedValue(\.editorComponentSidebarFocus) private var isComponentSidebarFocused
    @State private var pasteboard = EditorPasteboard()
    @State private var replayRequest: WorkflowReplayRequest?
    @State private var nativeUndoCommands = NativeUndoCommandState()

    private var applicationName: String {
        BuildIdentityPresentation.applicationName(
            bundleIdentifier: buildIdentity.launchBundleIdentifier, fallback: "Dust3D Editor")
    }

    private var nativeTextEditor: NSTextView? {
        _ = nativeUndoCommands.revision
        _ = isEditingText
        guard let view = NSApp.keyWindow?.firstResponder as? NSTextView, view.isEditable else { return nil }
        return view
    }

    private var hasTextEditingFocus: Bool {
        EditorCommandScope.hasTextEditingFocus(
            swiftUIFocus: isEditingText == true, hasNativeEditor: nativeTextEditor != nil)
    }

    private var canDeleteGraphSelection: Bool {
        EditorCommandScope.allowsGraphDelete(
            animationFocus: isAnimationFocused == true, nativeTextFocus: hasTextEditingFocus,
            componentSidebarFocus: isComponentSidebarFocused == true)
            && store?.canDeleteGraphSelection == true
    }

    private var rigAssignmentFocus: RigAssignmentCommandFocus {
        let window = NSApp.keyWindow
        return RigAssignmentCommandFocus(
            hasKeyWindow: window != nil,
            hasSheet: window?.attachedSheet != nil || window?.sheetParent != nil || NSApp.modalWindow != nil,
            textEditing: hasTextEditingFocus,
            animationFocused: isAnimationFocused == true)
    }

    var body: some Scene {
        DocumentGroup(newDocument: EditorFileDocument()) { file in
            EditorRootView(file: file.$document, sourceURL: file.fileURL)
                .environment(pasteboard)
                .id(file.document.identity)
        }
        .defaultSize(width: 1300, height: 820)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About \(applicationName)") {
                    ApplicationAboutPanel.show(applicationName: applicationName)
                }
            }
            CommandGroup(after: .help) {
                Button("Build Diagnostics") { openWindow(id: "build-diagnostics") }
                Button("Keyboard Shortcuts") { openWindow(id: "keyboard-shortcuts") }
                Divider()
                ForEach(ApplicationHelpLink.allCases, id: \.self) { link in
                    Button(link.title) { link.open() }
                }
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    EditorCommandScope.routeUndo(
                        hasNativeEditor: nativeTextEditor != nil,
                        nativeAction: { nativeTextEditor?.undoManager?.undo() }, documentAction: { store?.undo() })
                }
                .keyboardShortcut("z")
                .disabled(nativeTextEditor.map { $0.undoManager?.canUndo != true } ?? (store?.canUndo != true))
                Button("Redo") {
                    EditorCommandScope.routeUndo(
                        hasNativeEditor: nativeTextEditor != nil,
                        nativeAction: { nativeTextEditor?.undoManager?.redo() }, documentAction: { store?.redo() })
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(nativeTextEditor.map { $0.undoManager?.canRedo != true } ?? (store?.canRedo != true))
            }
            EditorClipboardCommands(pasteboard: pasteboard)
            CommandGroup(after: .saveItem) {
                Button("Save All") { EditorSaveAllCommand.perform(in: NSDocumentController.shared) }
            }
            EditorGeometryExportCommands()
            InspectorCommands()
            CommandGroup(after: .windowArrangement) {
                Button("Replay Steps…") {
                    guard let document = store?.snapshot?.document else { return }
                    replayRequest = WorkflowReplayRequest(document: document)
                    openWindow(id: "workflow-replay")
                }
                .disabled(store?.snapshot == nil)
            }
            CommandGroup(after: .toolbar) {
                #if MOTE3D_EXPERIMENTAL_GENERATED_RIG
                    Picker(
                        "Preview Mode",
                        selection: Binding(
                            get: { restPreviewActions?.mode ?? .model },
                            set: { restPreviewActions?.setMode($0) })
                    ) {
                        Text("Model").tag(GeneratedRigPreviewSession.Presentation.model)
                        Text("Generated Rest").tag(GeneratedRigPreviewSession.Presentation.generatedRest)
                    }
                    .disabled(restPreviewActions?.canChangeMode != true)
                    Menu("Generated Rest") {
                        Toggle(
                            "Show Model",
                            isOn: Binding(
                                get: { restPreviewActions?.showsModel == true },
                                set: { restPreviewActions?.setShowsModel($0) }))
                        Toggle(
                            "Show Bones",
                            isOn: Binding(
                                get: { restPreviewActions?.showsBones == true },
                                set: { restPreviewActions?.setShowsBones($0) }))
                        Toggle(
                            "Show Weights",
                            isOn: Binding(
                                get: { restPreviewActions?.showsWeights == true },
                                set: { restPreviewActions?.setShowsWeights($0) }))
                        Divider()
                        Button("Reveal Selected Joint") { restPreviewActions?.revealSelectedJoint() }
                            .disabled(restPreviewActions?.canRevealSelectedJoint != true)
                    }
                    .disabled(restPreviewActions?.canChangeVisibility != true)
                    Divider()
                #endif
                Toggle(
                    "Wireframe",
                    isOn: Binding(
                        get: { previewDisplayActions?.isWireframe == true },
                        set: { previewDisplayActions?.setWireframe($0) })
                )
                .disabled(previewDisplayActions?.canChangeWireframe != true)
                Toggle(
                    "Model Colors",
                    isOn: Binding(
                        get: { previewDisplayActions?.showsModelColors == true },
                        set: { previewDisplayActions?.setModelColors($0) })
                )
                .disabled(previewDisplayActions?.canChangeModelColors != true)
                Divider()
                Toggle(
                    "Rotate Preview Automatically",
                    isOn: Binding(
                        get: {
                            previewCameraActions?.supportsAutomaticOrbit == true
                                && store?.automaticallyOrbitsPreview == true
                        },
                        set: { enabled in
                            guard previewCameraActions?.canAutomaticallyOrbit == true else { return }
                            store?.automaticallyOrbitsPreview = enabled
                        })
                )
                .disabled(previewCameraActions?.canAutomaticallyOrbit != true)
                .help("Pauses during dragging, while inactive, and when Reduce Motion is enabled.")
                PreviewCameraMenu(
                    title: "Preview Camera", isEnabled: previewCameraActions?.canMove == true,
                    move: { previewCameraActions?.move($0) }, fit: { previewCameraActions?.fit() })
            }
            CommandMenu("Canvas") {
                Button("Switch Editing Profile") { _ = store?.switchSelectedCanvasProfile() }
                    .disabled(store?.canSwitchSelectedCanvasProfile != true)
                Divider()
                let setAddMode = store?.addPlacementToggleAction()
                Toggle(
                    "Add Nodes with Pointer",
                    isOn: Binding(
                        get: { store?.isAddingNodes == true },
                        set: { setAddMode?($0) })
                ).disabled(store?.isAddingNodes != true && store?.canBeginAddMode != true)
                Toggle(
                    "Move Origin",
                    isOn: Binding(get: { store?.isMovingOrigin == true }, set: { store?.setMovingOrigin($0) })
                )
                .disabled(
                    store?.canSave != true || store?.snapshot?.origin == nil || store?.isSelectingRigEdges == true)
                Button("Center Origin on Model") { store?.centerOriginOnModel() }
                    .disabled(store?.snapshot == nil || store?.isWorking != false)
                Button("Cancel Canvas Input") {
                    if store?.isAddingNodes == true { store?.cancelAddMode() } else { store?.cancelOriginDrag() }
                }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(store?.isMovingOrigin != true && store?.isAddingNodes != true)
                Divider()
                Button("Select All Nodes") { store?.selectAllNodes() }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(store?.snapshot == nil || store?.isWorking != false || store?.isSelectingRigEdges == true)
                Button("Select Whole Part") {
                    if let target = store?.wholePartActionTarget { store?.selectWholePart(target) }
                }
                .disabled(store?.wholePartActionTarget.map { store?.canSelectWholePart($0) == true } != true)
                Button("Clear Selection") { store?.select(nil) }
                    .disabled(store?.snapshot == nil || store?.isWorking != false)
                Menu("Part Visibility") {
                    CanvasHideAllPartsButton(store: store)
                    CanvasPartIsolationButtons(store: store)
                }
                Menu("Transform Selection") {
                    ForEach(SelectionTransform.allCases, id: \.self) { transform in
                        Button(transform.rawValue) { store?.transformSelection(transform) }
                            .disabled(store?.canTransformSelection(transform) != true)
                    }
                }
                .disabled(store?.canTransform != true)
                Button("Decrease Radius") { store?.adjustSelectionRadius(direction: -1) }
                    .disabled(store?.canAdjustRadiusInput != true)
                Button("Increase Radius") { store?.adjustSelectionRadius(direction: 1) }
                    .disabled(store?.canAdjustRadiusInput != true)
                CanvasRotationMenuButtons(
                    store: store,
                    animationFocus: isAnimationFocused == true,
                    nativeTextFocus: hasTextEditingFocus)
                CanvasPrecisionMenu(store: store)
                GraphColorizeMenu(store: store)
                DescendantRotationMenu(store: store)
                NodeConnectionControls(store: store)
                Button("Reduce Selected Nodes") { store?.reduceSelectedNodes() }
                    .disabled(store?.canReduceSelectedNodes != true)
                    .accessibilityLabel("Reduce Selected Nodes")
                Button("Reverse Edges Between Selected Nodes") { store?.reverseSelectedEdges() }
                    .disabled(store?.isWorking != false || store?.snapshot?.reversibleEdges.isEmpty != false)
                Button("Insert Midpoints on Selected Edges") { store?.insertSelectedEdgeMidpoints() }
                    .disabled(store?.canInsertEdgeMidpoint != true)
                    .accessibilityLabel("Insert Midpoints on Selected Edges")
                Button("Reverse Selected Edges") { store?.reverseExplicitlySelectedEdges() }
                    .disabled(store?.canReverseSelectedEdges != true)
                Button("Delete Graph Selection") {
                    guard canDeleteGraphSelection else { return }
                    store?.deleteSelection()
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(!canDeleteGraphSelection)
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
        .commands {
            CommandMenu("Rig") {
                if let rigAssignmentCommand, rigAssignmentCommand.canInvoke(in: store, focus: rigAssignmentFocus) {
                    Button("Assign Selected Edges to Bone") {
                        rigAssignmentCommand.invoke(in: store, focus: rigAssignmentFocus)
                    }
                    .keyboardShortcut(.return, modifiers: [.command])
                } else {
                    Button("Assign Selected Edges to Bone") {}
                        .disabled(true)
                }
            }
        }
        Window("Keyboard Shortcuts", id: "keyboard-shortcuts") {
            KeyboardShortcutHelpView()
        }
        .defaultSize(width: 740, height: 620)
        Window("Replay Steps", id: "workflow-replay") {
            Group {
                if let replayRequest {
                    WorkflowReplayView(document: replayRequest.document).id(replayRequest.id)
                } else {
                    ContentUnavailableView("No Replay", systemImage: "play.rectangle")
                }
            }
            .onDisappear { replayRequest = nil }
        }
        .defaultSize(width: 700, height: 540)
        Window("Build Diagnostics – \(applicationName)", id: "build-diagnostics") {
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
protocol EditorSaveAllDocumentControlling {
    var hasEditedDocuments: Bool { get }
    func saveAllDocuments(_ sender: Any?)
}

extension NSDocumentController: EditorSaveAllDocumentControlling {}

@MainActor
enum EditorSaveAllCommand {
    static func perform(in controller: any EditorSaveAllDocumentControlling) {
        guard controller.hasEditedDocuments else { return }
        controller.saveAllDocuments(nil)
    }
}

@MainActor
final class EditorAppDelegate: NSObject, NSApplicationDelegate {
    private let buildIdentity = RuntimeBuildIdentity.current
    private let launchDocument = EditorLaunchDocumentOpener(arguments: CommandLine.arguments)
    private let recoveryRequestGate = EditorRecoveryRequestGate()
    private let compositionRequestGate = EditorRecoveryRequestGate()

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        !launchDocument.shouldSuppressUntitledDocument
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildIdentity.logStartup(fallbackSubsystem: "org.dust3d.editor")
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(cancelReferenceComposition(_:)),
            name: EditorCompositionRecoveryChannel.notification, object: Bundle.main.bundleIdentifier)
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
            let requestID = EditorRecoveryRequestChannel.requestID(
                notification, bundleIdentifier: Bundle.main.bundleIdentifier,
                processIdentifier: ProcessInfo.processInfo.processIdentifier,
                notificationName: EditorRecoveryCopyChannel.notification)
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
        guard
            let requestID = EditorRecoveryRequestChannel.requestID(
                notification, bundleIdentifier: Bundle.main.bundleIdentifier,
                processIdentifier: ProcessInfo.processInfo.processIdentifier,
                notificationName: EditorCompositionRecoveryChannel.notification)
        else { return }
        let logger = Logger(
            subsystem: RuntimeBuildIdentity.current.loggingSubsystem(fallback: "org.dust3d.editor"),
            category: "recovery")
        guard compositionRequestGate.begin() else {
            logger.error(
                "operation=cancelReferenceComposition requestID=\(requestID.uuidString, privacy: .public) cause=alreadyPending"
            )
            return
        }
        Task { @MainActor in
            defer { compositionRequestGate.finish() }
            let cancelled = EditorCompositionRecovery.shared.cancelLatest()
            Logger(
                subsystem: RuntimeBuildIdentity.current.loggingSubsystem(fallback: "org.dust3d.editor"),
                category: "recovery"
            )
            .info(
                "operation=cancelReferenceComposition requestID=\(requestID.uuidString, privacy: .public) cancelled=\(cancelled)"
            )
        }
    }
}

private struct EditorAnimationFocusKey: FocusedValueKey { typealias Value = Bool }

private struct EditorTextEditingKey: FocusedValueKey { typealias Value = Bool }

private struct EditorComponentSidebarFocusKey: FocusedValueKey { typealias Value = Bool }

private struct EditorComponentSidebarSelectAllKey: FocusedValueKey {
    typealias Value = ComponentSidebarSelectAllTarget
}

private struct EditorStoreKey: FocusedValueKey { typealias Value = EditorStore }

extension FocusedValues {
    var editorAnimationFocus: Bool? {
        get { self[EditorAnimationFocusKey.self] }
        set { self[EditorAnimationFocusKey.self] = newValue }
    }

    var editorTextEditing: Bool? {
        get { self[EditorTextEditingKey.self] }
        set { self[EditorTextEditingKey.self] = newValue }
    }

    var editorComponentSidebarFocus: Bool? {
        get { self[EditorComponentSidebarFocusKey.self] }
        set { self[EditorComponentSidebarFocusKey.self] = newValue }
    }

    var editorComponentSidebarSelectAll: ComponentSidebarSelectAllTarget? {
        get { self[EditorComponentSidebarSelectAllKey.self] }
        set { self[EditorComponentSidebarSelectAllKey.self] = newValue }
    }

    var editorStore: EditorStore? {
        get { self[EditorStoreKey.self] }
        set { self[EditorStoreKey.self] = newValue }
    }
}
