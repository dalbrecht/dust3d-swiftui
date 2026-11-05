# ADR 0129: Canvas angle rotation

Status: accepted; full local native gate passed on 2026-11-01.

## Context

Qt exposes comma/period as minus/plus one-degree selection rotation. Its shared rotateSelected operation accepts a general angle, merges explicitly selected nodes with selected-edge endpoints, and chooses either a group centroid or a single-node descendant pivot. Native selection and descendant quarter-turn commands do not provide this exposed fine-angle workflow.

Qt reference: application/sources/document_window.cc:2498–2499; application/sources/skeleton_graphics_widget.cc:1087–1190,2070–2089. Shift-drag rotation and endpoint IK also call this Qt path, but require separate pointer/IK acceptance and are outside this keyboard/control checkpoint.

## Decision

Add one atomic general-angle command shared by the actor, window store, accessible inspector controls and bare comma/period commands. Accept finite signed angles within the supported signed 32-bit magnitude, reduce full turns before trigonometry and make exact full turns no-ops. Use exact cardinal-angle coefficients. Retain explicit selection, untouched coordinates and radii, and ordinary Undo/Redo semantics.

Use the deduplicated explicit-node/selected-edge endpoint set. With one effective node and a supported stored origin, keep that node fixed, exclude the nearest-origin direct neighbor as the parent when there is more than one neighbor, and traverse other connected branches using the existing descendant planner. A cycle can reconnect to that neighbor; do not replace traversal with a tree-only assumption. With multiple effective nodes, rotate editable participants around their centroid. A single node without a supported stored origin has no displacement. Front uses X/Y; Side uses Z/Y. Positive angles turn clockwise in the native canvas.

Preserve native axis and part locks. Qt temporarily disables position-related guards during this operation; reproducing that bypass would violate the established native editing policy. Read-only nodes remain fixed and are excluded from the editable group centroid, while traversal may pass through them to editable descendants. Preserve the existing documented tie policy and explicit stored-origin behavior rather than introducing automatic origin settlement.

Capture document identity/revision, explicit selection and constraint epochs before actor dispatch. Rendered action closures also retain plane and tool context, and reject obsolete callbacks. Keep punctuation out of text editing, animation focus, Add mode and origin movement; command, control, option and shift chords remain responder-owned. Existing explicit quarter-turn commands retain their semantics.

Keep the displayed general-angle draft as text and validate the complete locale-aware input. Invalid or incomplete text disables Apply instead of silently applying a previously valid numeric binding. Label the angle, plane and signed controls accessibly, and explain pivot and lock behavior.

## Verification

Require test-first evidence for arbitrary-angle coordinates in both planes, both signs, exact full-turn no-ops preserving Redo, mixed and edge-only selection, deduplication, single pivot, endpoints, cycles, absent origin, locks/read-only participants, invalid angles, rejected geometry and stale targets. Cover separate windows, preview refresh, one-step exact Undo, retained callbacks, tool/plane replacement, punctuation focus/modifier policy and invalid displayed drafts. Inspect light/dark hosted renders and run the full native gate before a local release.

Physical keyboard/field interaction, pointer rotation, IK, VoiceOver and broader Qt/HIG acceptance remain open. This command does not change the production core dependency or enable quarantined features.

Local verification: 60 support tests and 1,276 XCTest tests passed; maintained coverage gates, Qt-free linkage and isolated bundle/signature rebuild checks passed. New CanvasRotation coverage is 70/70 lines. Twenty final focused tests include native text-field Return/invalid draft and node-property Reset behavior. The node numeric editor was extracted without changing its draft lifecycle so Reset tests exercise that production component independently of unrelated inspector fields. Hosted light/dark control and full inspector renders were reviewed. Physical input and VoiceOver acceptance remain open.
