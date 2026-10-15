# Initial SwiftUI editor verification

October 14, 2026, Apple silicon development Mac. This is the existing-node editor
slice, not complete Dust3D feature parity. No C++ algorithms or engine pin changed.

## Automated evidence

`make ci` passes 48 XCTest tests, Swift formatting, native builds and Qt-free
source/linkage checks for both executables. New tests started red before the
editor APIs existed. Nine model tests cover stable selection, movement/radius,
undo/redo and branch invalidation, no-op/invalid-command atomicity, hidden/locked
parts, invalid edges, empty documents, front/side projection, independent actor
sessions, failed/cancelled open retaining the previous document, and routing.
Existing document tests continue to cover byte preservation and archive limits.

Measured executable-line coverage:

| Boundary | Covered / total | Coverage |
| --- | --- | --- |
| Swift mesh library | 66 / 67 | 98.51% |
| Document library | 376 / 388 | 96.91% |
| Editor model | 116 / 122 | 95.08% |
| Pure editor state | 42 / 42 | 100% |
| Pure undo history | 84 / 84 | 100% |

These numbers exclude SwiftUI, GPU code and inherited C++; they do not imply
whole-engine coverage. Both app bundles are staged and ad-hoc signature verified.

## Manual native checks

Used disposable copies of the committed Capsule fixture, preserving repo inputs.
Opened an existing model (3 nodes, 80 triangles), selected Node 2 in the list,
changed X from 0.5 to 0.6 and radius from 0.16 to 0.2, and pressed Apply. The
canvas and mesh changed. Command-Z restored both values; Command-Shift-Z reapplied
both. Canvas dragging changed X/Y while retaining Z and radius; one undo restored
the whole drag. Command-S cleared the edited indicator. Closed and reopened the
file: X=0.6, Y=0.5, Z=1, radius=0.2 persisted, with a fresh undo history. Native
Save As created a second `.ds3`; filesystem inspection confirmed edited XML values.
Negative radius was rejected with an error banner, without creating an undo step.
New created a separate empty document window with no selection/history/mesh.
The separate viewer opened the editor-saved file and rendered the same 80-triangle mesh after the shared renderer extraction. Final-build accessibility exposed distinct Node 1/2/3 labels after fixing an
inherited canvas label that masked the node names.

Opening both blank and existing document windows initially crashed in native
constraint updates with nested split/inspector containers. The plain pane shell
fixed the observed crash; both open paths were retested. See ADR 0004.

## Remaining evidence and scope

Native close/recovery/version browsing, forced termination, file-provider races,
keyboard-only/VoiceOver workflows, older macOS versions, and large-document GPU
performance need broader regression coverage. No UI snapshot baseline is claimed.
Native DocumentGroup owns autosave/unsaved close; no custom close-prompt or recovery
behavior is claimed as tested. New documents are empty: adding nodes/edges,
axis-specific lock semantics, multi-select, topology and full inspectors remain
later milestones. Part-level hidden/locked guards are implemented. Unknown assets
remain lossless even when procedural mesh preview cannot render them.
