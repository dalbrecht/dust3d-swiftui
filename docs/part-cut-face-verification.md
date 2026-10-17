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
and its regression tests still pass. That correction passed full `make ci` with
382 tests and zero failures, formatting,
native builds, coverage, Qt-free linkage and isolated bundle-rebuild checks.
Document line coverage at that stage was 2525/2609; other measured module totals above are
unchanged.

A second review regression covers inherited comma-decimal values such as 0,5.
The shared parser normalizes comma to dot while preserving original source bytes
on semantic no-ops, including redo. Tests cover rotation and deformation metadata,
controller input and actual core mesh/normal equivalence to dot-decimal rotation.
The new actual-core integration test initially failed against the old pin: its
C boundary rejected comma decimals before the inherited parser could accept them.
[Core PR 6](https://github.com/dalbrecht/dust3d-core/pull/6) supplies a failing-first
portable contract and boundary fix. It merged after clean automated review and
all six hosted jobs passed. Final full `make ci` now passes 385 tests with zero
failures against exact pin `7d37f08299dffb6e1c9d848bea3ee974169449b9`, including
formatting, native builds, coverage, Qt-free linkage and isolated signed bundle
rebuild checks. Final document line coverage is 2528/2612; other measured module
totals above are unchanged.
