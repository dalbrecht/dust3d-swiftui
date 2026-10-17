# Editor preview source verification

Issue #114; ADR 0057. Uses the reviewed SDK/core dependency already pinned by #113.

## Contracts and evidence

The initial tests failed on missing store source properties and service budget
configuration before implementation. Seven new tests plus existing lifecycle
regressions cover actual current mesh/hint pairing, stale metadata suppression,
obsolete replacement/stop rejection, actual source-budget fallback, successful
empty output, cache reuse, preserved archive bytes/publications and undo state.
Controlled backends cover status-specific retry, both original failure causes,
deduplicated messages, cancellation during each attempt, and no fallback on
invalid/unsupported input. Existing serial/reset regressions remain in the gate.

No production fault switches or forged native handles are introduced. Real SDK
fixtures exercise ordinary fallback and source provenance. Replacement uses
models with different node counts and awaits old task completion before asserting
that neither old geometry nor old metadata wins.

The full suite passes 513 tests with two existing no-Metal-device skips. Render
coverage exercises both notice types at the 320-point preview width, short/long
messages and light/dark appearances. All eight PNGs were visually inspected:
readable semantic colors and wrapped messages without clipping. Offscreen renders
activate no application and create no visible window or new QA bundle identity.
No pixel baseline was invented. The interface-polish skill review retained system
fonts, matched SF Symbol weight, structural dividers and static feedback; stronger
warning colors and repeated entrance animation would overemphasize optional data.

Measured line coverage: preview service 102/102 (100%); diagnostic notice
26/26 (100%); whole existing EditorStore 654/765 (85.49%). The store
remains below the shared application target; this stage does not claim otherwise.
Full `make ci` also passes formatting, native build, enforced module coverage,
Qt-free linkage and isolated signed bundle rebuild/archive checks.

## Limits

This is source metadata adoption, not selection/picking or material/rig parity.
Native GPU, whole-window layout under simultaneous warnings, keyboard/VoiceOver,
and native/Qt modifier acceptance remain separate checks. Existing GPU skips are
not passes. Swift coverage does not measure inherited C++ coverage. Source failure
may require a second generation; no latency/resource bound or hard cancellation
claim is made. Editing, undo and save do not depend on these derived results.
