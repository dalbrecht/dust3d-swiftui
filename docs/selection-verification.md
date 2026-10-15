# Multi-node selection verification

This stage adds per-window selection sets, sidebar Command/Shift selection, canvas Command-click, Select All Nodes (Command-Shift-A), group dragging, relative coordinate movement, and group deletion. Read-only nodes can be inspected and remain unchanged during group operations. Selection and interaction locks never enter the archive.

## Automated evidence

`make ci` passed 73 tests. Measured line coverage: document library 641/656 (97.71%), editor model 281/287 (97.91%), pure editor state 181/181 and undo domain 92/92 (both 100%). The gate checks formatting, both app builds, XCTest, coverage thresholds, and Qt-free linkage. Selection regressions exercise transient/atomic selection, deterministic primary selection, selected-anchor and unselected-anchor dragging, read-only filtering, locks, out-of-bounds/invalid input rejection, exact archive restoration with one undo, redo preservation for no-ops, selection pruning after deletion, unknown node attributes, opaque archive assets, actor entry points, and bulk command validation/net-zero transactions.

The inherited C++ engine and native GPU/UI are separate verification scopes; the new pure state/history coverage does not imply full engine or UI coverage.

## Native manual evidence

Verified on macOS with the isolated `org.dust3d.editor.qa` app and a disposable copy of the Capsule fixture. The user's running editor and its unsaved document were left alone.

- Command-Shift-A selected all three nodes without dirtying the document or enabling Undo.
- Canvas Command-click removed one node from the group and updated the sidebar/inspector.
- Relative Y movement changed only the two selected nodes. Saved XML confirmed Y values .35/.5/.85 with original X/Z coordinates.
- With X locked, a diagonal drag moved both selected nodes vertically, leaving the unselected node fixed. Handles, edges, and mesh preview updated. One Undo reversed the entire drag.
- Delete Selected Nodes removed both selected nodes and their incident edges. One Undo restored all three nodes; Redo removed them together again.
- Save, close, and reopen retained geometry and cleared transient selection, locks, and history. The reopened model generated 80 triangles.
- Native sidebar Shift-click selected the whole range and showed the group inspector.

No Qt GUI comparison, VoiceOver pass, oldest-supported-macOS run, large-document performance baseline, or visual pixel baseline is claimed. Marquee/scaling/clipboard and graph split/merge parity remain pending.
