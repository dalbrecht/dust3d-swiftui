# Isolated loop-interior fill verification

Issue #95 adds a lossless fillLoopInterior part command and role-specific native
controls. The source flag remains available for every role; only stitching-loop
roles show the control and only isolated closed loops consume it geometrically.

Three document tests first failed without the API, then passed: defaults,
known/unknown spellings, byte-preserving reads/no-ops, redo preservation, missing
owners, exact archive history, role/graph/readonly-flag preservation and opaque
XML/assets surviving save/reparse. Explicit false removes only a changed flag.

The controller test first failed without its store method. Three core/controller
tests now verify finite changed geometry on an isolated loop, unchanged existing
surfaces for a connected-loop flag edit, exact undo/redo, no-op redo, missing-part
failure isolation, selection/camera retention and opaque asset preservation.
The isolated fixture includes a separate uncombined model so clearing the fill
leaves a nonempty scene. A concentric-loop fixture is retained to verify the
algorithm's intentional no-effect behavior on already connected boundaries.

The UI test first failed without the control. Nine render tests now cover
part/component inspectors and on/off/unsupported loop flags in light/dark
appearances without changing bytes or history. Transient artifacts under
/private/tmp/dust3d-part-loop-ui-qa are inspected at the actual 250-point width;
labels, checkbox/menu states and explanatory text are readable and unclipped.
No snapshot baseline is committed.

Full `make ci` passed on 2026-10-17: 423 tests, zero failures, formatting,
native builds, coverage, Qt-free linkage and isolated bundle-rebuild checks.
Measured lines: document 2678/2762, editor model 1417/1423, pure editor state
524/524, undo 97/97 and mesh 66/67. These do not measure native UI/Metal coverage. No dependency, core revision, CI configuration or
application identity changes.

Native input, menu transitions, Save/Undo/Redo menus, VoiceOver, GPU rendering
and Qt differential/manifold acceptance remain pending. Reuse
org.dust3d.editor.combine-qa. Hollowing remains open in #96; wrapping, broader M3
and M4–M8 are incomplete. Full feature parity is not claimed.

## Review regression: the only filled loop

Automated review identified that the earlier isolated fixture's unrelated model
left the lone-loop empty case uncovered. The new lone-loop test first reproduced
a retained stale mesh and generic generation failure after clearing fill. Core
PR #8 adds an explicit successful-empty status, with all twelve portable Debug
and sanitizer contracts and all six hosted Linux/macOS jobs passing after a
clean review. The Apple manifest/lock now pin its reviewed merge revision.

MeshLoader.loadIfPresent maps only NO_GEOMETRY to nil. Genuine malformed and
nonfinite generation errors retain original statuses/messages. Request-checked
succeedEmpty clears geometry without letting obsolete/duplicate completions
erase newer output. The lone-loop regression verifies nil mesh, no error/stale
state, retained selection/camera, exact undo/redo and restored filled geometry.
A real generation failure still retains the previous mesh as stale. Pure tests
cover request identity and loaded-empty descriptions. The production placeholder
is rendered in light/dark modes without GPU setup.

Fifteen focused integration/state/description tests and ten renderer tests pass.
Fresh full-gate results follow this earlier 423-test record. Native input and GPU
acceptance remain pending.

The fresh full `make ci` passes 432 tests with zero failures, formatting, native
builds, coverage, Qt-free linkage and isolated bundle-rebuild checks. Measured
lines: mesh 73/74, document 2678/2762, editor model 1428/1434, pure editor state
529/529 and undo 97/97. Generated-empty placeholder output from the final gate
was inspected in light/dark modes with semantic primary text for readability.
These totals do not measure native UI/Metal or inherited C++ coverage.


Subsequent core-pin correction: reviewed core PR #15 bounds inverse-cosine input.
Previously rejected .225 openings and straight profiles now have finite-output
coverage. Genuine generation-failure coverage uses a negative legacy wrap offset
that removes the complete surface, preserving status 3 and stale-preview behavior.
See [current controller verification](wrapping-controller-verification.md). Core
#14 separately tracks collapsed/zero-area geometry; no topology parity claim.
