# Imported surface adoption verification

Tracked by #155; ADR 0073. SwiftPM manifest and committed resolution pin the
reviewed merged core revision 0a83c3e3a59da4bafb5e3e83023fffd7df5cca90.

## Local gate

`make ci` passed with 733 XCTest tests (186.724 seconds), 31 build-support tests,
strict formatting, native build, Qt-free source/link checks and bundle-rebuild
verification for separate editor/viewer identities and both preview extensions.

Measured library line coverage: Dust3DKit 1963/1989, Document 3471/3559, editor
model 1545/1551; the enforced pure editor state, undo and orbit camera scopes are
100%. The three new surface files together measure 203/204 lines (99.51%): copy
141 lines with one missed, loader 46/46, value types 17/17. The defensive invalid
native component classification path is not exercised by valid core catalogs.
LLVM's Swift branch report has no branch data; no branch-coverage percentage is
claimed. These measurements do not instrument the inherited C++ engine or prove
GPU/Qt rendered parity.

## Acceptance cases

Fifteen focused tests use the real core C owner and independently authored MIT
DS3/GLB fixtures, plus raw malformed-record boundary cases. They verify exported
geometry/triangle alignment, source corner RGB/alpha independent of factors and
preview opacity, linear/sRGB tags, explicit unknown procedural records, original
and generated mirror catalogs, independent lifetimes, exact/one-byte-short
native and Swift quotas, typed original native errors, checked counts/indices,
finite UV/RGBA and repeat-coordinate retention. Original GLB bytes survive node
edits, undo/redo and save/reopen. Background operations preserve original errors
and discard results on cancellation before/during synchronous work.

## Remaining work

The current app still presents imported geometry with its explicit unapplied
material warning. This API is not wired into the renderer and is not packed UV
metadata. Imported sampling, atlas/bake integration, PBR/alpha display, fully
rendered Quick Look/thumbnail compatibility and textured export remain M4
acceptance work. A current native app screenshot is captured with PR publication;
it demonstrates current geometry preview behavior, not imported texture parity.

## Automated review regressions

Two P2 findings are addressed with regressions: model identity equality/hash must
preserve byte-distinct Unicode representations, and a direct synchronous copy
must not publish after cancellation during geometry copying. The latter was
reproduced as a behavioral failure after a real native geometry copy, then fixed
with a final cancellation check. Fifteen focused tests now cover these cases.
The updated full gate passed all 733 tests, coverage and bundle checks. The
measurements above describe the corrected source. Exact-head hosted CI and
automated re-review remain required before merge.

A subsequent P2 identified the same cross-API key issue on component IDs. Both
catalogs now expose one bounded ImportedSurfaceIdentity type with byte-exact
Hashable semantics. A component dictionary regression reproduced the overwrite
before the fix; all fifteen focused tests pass after it. The updated full gate passed all 733 tests, coverage and bundle checks.
Exact-head hosted checks and automated review are still required before merge.
