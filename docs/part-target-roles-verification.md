# Procedural part target roles verification

Issue #91 adds Model, CutFace, StitchingLine and StitchingLoop metadata commands
and native controls. Unknown/ImportedModel source roles remain unsupported and
preserved until explicit replacement. Imported-model support belongs to M4.

## Evidence

Three domain tests first failed without the role API, then passed: absent/empty
and explicit defaults, all supported roles, unsupported spellings, read-only
flags, source nodes, opaque metadata/assets, save/reparse, exact undo/redo,
semantic no-ops preserving source spellings/redo, and missing-owner rejection.

A preview regression first failed at runtime because profile-only parts were
counted as joined contributors. The pure snapshot now excludes CutFace and
disabled parts while retaining editable nodes. Tests include mixed profiles and
model/stitching roles with disabled-state transitions. A real-core controller
test verifies nonempty Model geometry, intentional profile-only clearing without
a stale/error state, retained nodes/selection/camera, exact archive history,
Model no-op preserving redo and regenerated Model geometry after restoration.

The control test first failed without the store method and view. Seven render
tests now include every supported role, future/ImportedModel source states and
the actual 250-point inspector, preserving bytes/history in light/dark modes.
Transient artifacts under /private/tmp/dust3d-part-target-ui-qa were inspected
for readable captions, selected roles, unsupported guidance and unclipped controls.
The fixtures for standalone stitching roles establish rendering/preservation,
not a successfully configured stitched surface.

Full `make ci` passed on 2026-10-17: 405 tests, zero failures, formatting,
native builds, coverage, Qt-free linkage and isolated bundle-rebuild regression.
Measured lines: document 2558/2642, editor model 1417/1423, pure editor state
524/524, undo 97/97 and mesh 66/67. These do not measure native UI/Metal coverage. No new dependencies, core revision, CI configuration
or app identity is introduced.

## Remaining acceptance

Native picker/keyboard/pointer, Save/Undo/Redo menus, VoiceOver and GPU/root
empty-preview presentation checks remain pending without desktop input. Reuse
org.dust3d.editor.combine-qa for native QA. Component stitching parameters and
configured surface fixtures, Qt differential roles, other M3 modifier families
and M4–M8 remain incomplete. Full modeling parity is not claimed.
