# 0049 — Lossless group wrapping foundations

Status: Accepted for the document foundation; native controls follow separately.

## Context

The inherited generator supports Skin and Cloth wrapping with mode-dependent
optional defaults. Switching modes must not erase explicit source parameters.
The Qt inspector permits 64–20000 faces, while the engine clamps up to 40000.
Existing source values outside the editing range must survive unrelated edits.

## Decision

Expose typed `ComponentWrapMode`, `ComponentWrappingScalarProperty` and immutable
`ComponentWrappingSettings`. Group-only commands change mode, keep-children,
whole face count or one bounded finite scalar. Absent/empty optional values use
inherited defaults; unknown modes do not invent mode-dependent defaults. Explicit
unsupported values remain nil in the interpretation and unchanged in the archive.
Semantic no-ops retain source spellings, bytes and redo. Resetting a changed value
to its current mode's default removes only that attribute. Mode changes touch
only `wrap`, retaining all parameters, opaque XML and assets.

Pin core to reviewed `49faaf333255199cdbfaf8b46be445e75d55e55d` (core PR #12).
This adds numeric validation for all consumed wrapping fields and includes the
portable configured-stitching contracts from core PR #10. No second adapter or
new dependency is introduced. Domain commands remain synchronous pure document
transformations; existing EditorSession isolates XML work and publishes batches
atomically off the main actor.

## Consequences and limits

Explicit edits use Qt inspector ranges, including 20000 maximum faces. Existing
40000-face data stays preserved and uninterpreted until an explicit replacement.
Weights binding, patterns, colors, belly and wrinkle metadata remain intact;
their editable interfaces follow in later focused stages. No native UI changes
or UI/GPU acceptance is claimed by this foundation.

Synthetic one-sphere tests prove both modes, increased density, keep-children,
scalar configurations, source graph preservation and exact history. Core issue
#13 records a real inherited nonfinite-opening defect at 64 faces and opening
0.225; the C ABI must continue reporting generation failure. The same opening
passes at 256 faces, and 0.1 passes at 64. Full wrapping boundary/interacting
geometry acceptance remains incomplete until that issue and broader corpus work
are resolved. Do not weaken finite validation or silently substitute geometry.
