# ADR 0174: Canvas context actions and secondary-click safety

Status: Qt modeling and Apple #343 follow-up.

The Qt SkeletonGraphicsWidget::showContextMenu at lines 201–405 exposes graph
editing near the selection. Its Add-mode branch switches to Select and returns
without opening a menu. Native NodeCanvas already had color and precision
context menus and a targeted Select Whole Part action; those were not absent.
Add the existing midpoint, reverse, reduce and delete operations to those menus.
Qt's context-menu Split is midpoint insertion, not edge disconnection.

A GraphSelectionActionTarget freezes initial eligibility and document, selection
and constraint epochs. The actor checks cancellation, current source and captured
availability, then synchronously delegates to existing operations. There is no
suspension between validation and delegation, and no duplicate UUID allocation,
part-splitting or undo implementation. Store actions also retain the originating
Add-mode UUID so retired menus cannot acquire a later interaction context.

Keep SwiftUI/session state as the source of truth. A pure copied-value classifier
separates primary, context-menu, Add-cancellation and unhandled button intent.
The existing narrow AppKit pointer views classify Control-left before primary
placement, selection or drag setup. Secondary requests cancel Add through a
captured mode lease and return; ordinary requests retain responder-chain routing.
The canvas menu(for:) boundary also checks Add mode for contextual menu requests.
Node activation is cleared before forwarding a normal secondary request.

Apple's [context-menu guidance](https://developer.apple.com/design/human-interface-guidelines/context-menus)
favors relevant commands, main-interface alternatives, shallow submenus and
omitting unavailable context items. The graph submenu contains only initially
available edits, with Delete last and marked destructive. Contextual color and
precision views filter unavailable actions while ordinary menu defaults retain
disabled commands for discovery. All edits remain available through existing
Canvas menus or inspectors; no new keyboard shortcuts are introduced.

[NSView documentation](https://developer.apple.com/documentation/appkit/nsview)
explains normal rightMouseDown/menu(for:) and responder routing. The implementation
uses existing events without constructing or synthesizing NSEvent values.

TDD pure tests cover button/modifier decisions, every actual actor delegate,
initial availability, Undo/Redo, stale and unavailable targets, cancellation,
independent windows, Add-mode ABA, ghost cancellation and menu ordering. No new
NSView, NSEvent, GUI, Metal-device or native-generation runtime probes are added.
These tests and SDK compilation cannot establish actual hosted menu presentation,
physical pointing, focus or VoiceOver behavior. Those acceptance checks and full
Qt/HIG parity remain open. Production pin and all runtime quarantines are unchanged.
