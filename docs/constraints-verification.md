# Editing constraint verification

October 14, 2026, Apple silicon development Mac. Core dependency pin unchanged.

`make ci` passes 65 tests, format/build checks and both executable Qt-link gates.
Five new tests started red before implementation and cover all 16 lock combinations,
transient state, independent sessions, direct and batched node setters, rejected
invalid inputs, opaque asset retention, undo/redo bypassing current locks and
front/side projected drag coordinates. Pure editor state remains 101/101 lines
(100%); history 91/91 (100%); editor model 185/191 (96.86%); document library
610/620 (98.39%); mesh library 66/67 (98.51%). Metrics exclude SwiftUI, GPU and
inherited C++ code.

Native checks used a signed isolated QA bundle and a disposable Capsule copy,
leaving the running main editor's edited document untouched. Selecting Node 2
and locking X disabled its X field without changing the edited indicator or undo
availability. Dragging diagonally retained X=0.5 and changed only Y; undo restored
it. Applying Y=0.6/radius=0.2 succeeded with X locked. Turning on all locks disabled
all numeric fields; Command-Option-Z toggled the Z control. A fully locked drag
created no undo entry: one undo restored Y=0.5/radius=0.16 and exhausted history,
with all locks still enabled; redo restored the edit.

Save cleared the native edited indicator. A new window started with all locks off;
changing a lock there left it unedited and closed without a save prompt. The first
window retained all its locks. Closing and reopening the saved model reset locks
and history but retained X=0.5/Y=0.6/Z=1/radius=0.2. File inspection confirmed
canvas and part metadata were unchanged and no interaction-lock fields were added.
Locking X with an unapplied X=0.7 draft reset the disabled field to committed X=0.5.

No full Qt GUI parity, VoiceOver, older-macOS or large-document performance claim
is made. The source Qt lock semantics are documented in ADR 0005.
