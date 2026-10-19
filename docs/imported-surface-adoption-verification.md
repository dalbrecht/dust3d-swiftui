# Imported surface adoption verification

Tracked by #155; ADR 0073. SwiftPM manifest and committed resolution pin the
reviewed merged core revision 0a83c3e3a59da4bafb5e3e83023fffd7df5cca90.

## Local gate

`make ci` passed with 730 XCTest tests (117.238 seconds), 31 build-support tests,
strict formatting, native build, Qt-free source/link checks and bundle-rebuild
verification for separate editor/viewer identities and both preview extensions.

Measured library line coverage: Dust3DKit 1951/1977, Document 3471/3559, editor
model 1545/1551; the enforced pure editor state, undo and orbit camera scopes are
100%. The three new surface files together measure 191/192 lines (99.48%): copy
138 lines with one missed, loader 46/46, value types 8/8. The defensive invalid
native component classification path is not exercised by valid core catalogs.
LLVM's Swift branch report has no branch data; no branch-coverage percentage is
claimed. These measurements do not instrument the inherited C++ engine or prove
GPU/Qt rendered parity.

## Acceptance cases

Twelve focused tests use the real core C owner and independently authored MIT
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
