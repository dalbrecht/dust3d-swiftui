# Part deformation foundation verification

Tracks #81 and #62. Decision: [ADR 0041](adr/0041-part-deformation-foundations.md).

## Automated evidence

Document tests failed first for missing metadata/commands, then passed with the
implementation. Controller tests failed first for missing actions. Contracts
cover absent/default and unsupported values, exact boolean spellings, empty
scale ambiguity, finite 0...2 bounds, near-default 0.995/1.005 retention, exact
undo/redo and semantic no-op byte/redo preservation, identities, node deformation,
unknown metadata/assets and reopen. Invalid numeric input is rejected; imported
unsupported data is preserved until an explicit supported replacement.

A session test applies scale/unified changes followed by an invalid scale and
verifies atomic rollback with unchanged history, selection and interaction locks.
A successful two-command batch undoes/redoes in one step.

Actual-core tests use a three-node tapered part with different radii. Width and
thickness at 0.995 change generated positions while keeping finite geometry and
unit normals. Unified deformation at width 0.5 changes the tapered mesh. Controller
changes publish once, preserve selection/camera, ignore no-ops and restore exact
archive/mesh history. Empty, nonnumeric, nonfinite and out-of-range controller
input publishes nothing. Both zero and two generate nonempty finite/unit-normal
meshes for each scale on this fixture; this is not a closed-topology assertion
for a zero-width cross-section or a proof of every interacting modifier.

Full `make ci` passed on 2026-10-16: 369 tests, zero failures, formatting,
native builds, coverage, Qt-free linkage and isolated signed bundle-rebuild checks.
Measured line coverage: document 2415/2498, editor model 1394/1400, pure editor
state 523/523, undo domain 97/97, orbit camera 33/33 and mesh library 66/67.

## Remaining acceptance

This stage adds no inspector UI. Native controls and rendered Save/Undo/Redo
acceptance remain a follow-up; the QA desktop is locked and the user is unavailable
for manual actions. Reuse the existing QA app path and identity when available.
Qt numerical/render differential acceptance, per-node deformation editing and
other M3 modifier families remain pending. No full modeling parity, native UI
coverage or inherited core coverage claim is made.
