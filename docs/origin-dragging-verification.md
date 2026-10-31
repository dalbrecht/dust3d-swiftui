# Origin dragging verification

## Pointer identity follow-up

The origin handle uses the shared AppKit pointer boundary with a rectangular
44-point hit target. Each pointer activation has its own token; late update,
finish and interruption callbacks cannot affect a newer gesture. A click clears
only its draft and leaves Move Origin enabled. Escape cancels active origin mode
before a concurrent cancellable export; when origin mode is inactive it retains
the export cancellation behavior. Locks and the session's document/revision
checks remain authoritative.

The token regression was written first and failed to compile against the former
untokenized API. A separate red-first policy test identified the simultaneous
origin/export Escape routing. Nineteen focused origin, reference-image and pointer
tests passed, including a hosted origin handle whose resolved hit target receives
direct synthetic drag and Escape events. This does not prove actual window-server
dispatch, held physical pointer behavior or VoiceOver. Those native checks remain
open; no existing app process was contacted for this follow-up. A combined full
gate is required before delivery.

The full local `make ci` gate passes 230 XCTest tests, native builds, strict formatting, coverage and Qt-free linkage for both apps. Measured Swift coverage: mesh 66/67 lines; document 1852/1927; editor model 924/930; pure editor state 419/419 and undo domain 97/97 (100%). This does not measure inherited C++ coverage.

TDD first rejected the absent drag type/session commit API. A later regression failed when toggling a lock on and off revived a gesture; the constraint epoch fixes it. Tests now cover both planes, every axis/radius lock, stable captured projection, no-op/invalid/oversized input, unavailable origins, exact one-step undo/redo, replacement at the same revision, cross-window identity, stale revision/constraints, readonly/hidden/disabled parts, node/part/opaque-asset retention, unknown XML, save/reopen, cancellation preserving redo, load/plane/lock/stop cancellation and canvas-only refitting without mesh-camera reset.

Native QA used a separately staged/signed app and a disposable Capsule.ds3 copy:

- Inspected the rendered marker, explicit mode, Front/Side picker, existing mesh and numeric inspector. No reference design is supplied, so no pixel baseline is invented.
- Selected Node 2 at the overlapping origin via its accessibility action with mode off; this verifies selection routing, not physical pointer hit testing.
- Enabled Move Origin and pressed Escape in Front and Side; mode exited and Undo stayed disabled.
- Edited Origin X from 0.5 to 0.75 through the keyboard-accessible fields, applied, observed the marker update and Undo becoming available, and undid back to 0.5. The 80-triangle preview remained available.
- Compared the restored disposable archive with the original fixture: byte-identical.

**Remaining native check:** physical pointer dragging/cancellation and overlap hit testing. Computer-use coordinate click/drag calls repeatedly returned `noWindowsAvailable` while screenshots, keyboard and accessibility actions worked, including after retrying with a unique QA bundle/process identity. Controller/projection tests exercise the gesture callbacks, but this is not a claim that a physical drag or Escape during a held drag was validated. VoiceOver certification, rotated/mixed-profile comparisons, automatic settlement and full M2 acceptance remain pending. See [ADR 0022](adr/0022-origin-dragging.md).
