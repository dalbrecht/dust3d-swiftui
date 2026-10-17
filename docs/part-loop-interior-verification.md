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
