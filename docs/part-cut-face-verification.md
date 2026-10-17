# Part cut-face foundation verification

Tracks #83 and #62. Decision: [ADR 0042](adr/0042-part-cut-face-foundations.md).

## Automated evidence

Six document tests first failed for absent APIs, then passed. They cover defaults,
four presets, unsupported values, exact braced/unbraced profile identities,
normalized rotation bounds and fine values, parser underflow, node overrides,
unknown metadata/assets, reopen, semantic no-op bytes/redo and exact history.
New links reject missing/unsupported targets and self, part and node dependency
cycles without changing the source. An isolated session test rejects a cyclic
batch after a valid rotation, leaving history, selection and interaction locks
unchanged; a successful two-command batch undoes/redoes together.

Four controller tests first failed for missing actions. They use a real three-node
part plus an independently serialized two-node profile marked target CutFace.
Every preset regenerates finite unit-normal geometry; non-Quad presets and linked
profiles change geometry relative to the Quad fallback baseline. A 0.25 half-turn
rotation changes Triangle geometry. Endpoint -1/1 and the minimum normal double
also generate finite/unit-normal meshes. Invalid controller input publishes no
change. Successful edits retain camera/selection, publish once, ignore no-ops and
restore exact archive and mesh output through Undo/Redo.

The extracted EngineScalar helper retains the previous deformation regressions;
the combined targeted run passed 16 tests before controller integration. The
complete cut-face targeted run passes 11 tests. Full `make ci` passed on
2026-10-17: 381 tests with zero failures, formatting, native builds, coverage,
Qt-free linkage and isolated signed bundle-rebuild checks. Measured line coverage:
document 2504/2588, editor model 1394/1400, pure editor state 523/523, undo domain
97/97, orbit camera 33/33 and mesh library 66/67.

## Remaining acceptance

No inspector controls are added by this PR. Native rendered editing, Save/Undo/Redo,
keyboard/VoiceOver and Qt differential validation remain pending while the QA
desktop is locked and the user is unavailable for manual actions. Reuse the
existing QA app identity when it is available. Per-node cut-face/rotation editing,
profile authoring controls, complex/ring profiles, modifier combinations and other
M3 families remain pending. Tests prove these fixtures, not complete profile or
modeling parity, native UI coverage or inherited C++ coverage.

## Review regressions

Failing-first tests reproduce underflowed controller text resetting a nonzero
rotation and unrelated imported cycles blocking preset/independent-link edits.
Controllers now share the package-scoped underflow-aware scalar parser, including
for deformation. Exponent-spelled true zero remains valid and undoable. Targeted
link validation rejects paths back to the edited owner while terminating safely
on pre-existing cycles elsewhere. Existing part-joining validation remains global
and its regression tests still pass. The corrected full `make ci` passes 382 tests with zero failures, formatting,
native builds, coverage, Qt-free linkage and isolated bundle-rebuild checks.
Document line coverage is now 2525/2609; other measured module totals above are
unchanged.
