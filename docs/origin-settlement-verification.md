# Explicit origin settlement verification

Full `make ci` passes 234 XCTest tests, strict formatting, native builds, coverage and both Qt-free app linkage checks. Swift coverage: mesh 66/67; document 1852/1927; model 953/959; pure editor state 424/424 and undo 97/97 (100%). Inherited C++ coverage is not measured here.

TDD first failed against the absent settlement type/state/session APIs. Four new tests cover unequal radii, every part flag, selection independence, negative coordinates, extreme valid bounds, nonfinite/oversized/negative-radius rejection, empty models, each axis/radius lock, unavailable-origin initialization, no-op redo preservation, exact one-step undo/redo and save/reopen. The controller test verifies node preservation, active-mode cancellation, preview regeneration and canvas-only refit without mesh-camera reset. Existing origin command tests retain opaque-asset and unknown-XML preservation coverage.

Native QA on a disposable Capsule.ds3 copy:

1. Expanded Document Origin and inspected the new accessible Center Origin on Model control/help.
2. Set X to 5 using the numeric fields, applied, then centered. The marker/fields returned to (0.5,0.5,1); the 80-triangle preview remained available.
3. Undid once: X returned to 5, showing settlement is a separate history step. Enabled X lock and centered again: X stayed 5 and Redo remained available. Unlocked and exercised Redo/Undo.
4. Undid the original numeric edit, saved and compared the disposable archive to the original fixture: byte-identical. Final rendered window showed the marker, new control and mesh.

The new UI is inspected without inventing an unavailable reference-design baseline. No physical origin-drag result is claimed (tracked in #45). No automatic Qt settlement, rotated/mixed-profile GUI differential result, VoiceOver certification or full M2 parity is claimed. See [ADR 0023](adr/0023-explicit-origin-settlement.md).
