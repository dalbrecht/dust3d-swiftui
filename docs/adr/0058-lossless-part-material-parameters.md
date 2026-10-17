# ADR 0058: Lossless part material parameters

Status: Accepted for implementation; issue #116.

## Context

The reference editor stores part metallic/roughness/glow separately from component
colors/images and bakes them in its Qt-dependent UV workflow. Source edits need
lossless persistence before the portable baking and PBR rendering stages exist.
This archive/controller/UI work is independent of remaining M3 geometry acceptance;
it does not waive that milestone's checks.

## Decision

Use exact existing attribute names `metallic`, `roughness`, `emissive`. Retain the
reference UI bounds: metallic/roughness 0–1; glow 0–2. Defaults are 0, 1, 0.
Reuse the shared engine scalar parser for legacy comma decimals, finite values and
Float representability. Preserve absent defaults and all unsupported source
spellings without rewriting. A semantic no-op retains original bytes and redo.
A genuine default edit removes that attribute only. Reject invalid values before
committing any document/history change, using a typed document error.

Route one explicit Apply through existing document commands/session history and
controller publication without regenerating unchanged preview geometry. Numeric drafts are transient; Escape/Reset Draft restores
the current source value. Unknown metadata requires an explicit replacement.
Offer material controls for Model parts, matching the reference inspector. Keep
stored values for every role; changing roles must not erase material metadata.
Explain in the inspector that the current preview does not display these effects.

## Consequences

Exact unknown XML/assets and undo/redo/save/reopen survive edits. There is no new
image library, adapter, dependency pin or renderer behavior. The reference Qt UI
permits glow 2, while its material bake clamps the factor to 1: preserve source
intent instead of narrowing the stored range to match that rendering limitation.
Portable UV/bake extraction, color/alpha/images, PBR rendering, imports and broader
native/Qt acceptance remain separate required stages of full M4.
