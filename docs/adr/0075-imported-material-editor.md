# ADR 0075: Imported material adoption in the editor

Status: implemented locally for #159; full local gate and scoped native acceptance pass; hosted review/CI pending.

## Decision

Reuse ADR 0074's bounded archive preparation and owned Metal resources in the
separate editor. The native core pin and archive/document commands do not change.
Generalize the editor's transient `MeshPreviewState` output from baked-only data
to `MeshMaterialContent`, a mutually exclusive baked/imported representation.
Procedural documents continue through the existing retained-asset baker.

Every request captures one immutable document snapshot. Document changes cancel
pending work; the existing request and scope identities reject old success/error
results. Material-only changes may reuse ordinary geometry; geometry-changing
edits, undo/redo and replacement regenerate the preview and its source hints.
Material uploads preserve viewport camera/wireframe and never manufacture picking
hints from a different representation. Source hints remain guarded by the existing
current ordinary-preview state.

Only a current completed GPU frame removes the recognized imported-material
warning. A material GPU failure must carry the same current viewport revision;
old callbacks cannot clear a newer document's output. Loading includes CPU
preparation and current-frame presentation. Original native/codec/quota/GPU causes
remain visible with ordinary geometry and Retry Materials. Material output,
progress, errors and GPU acknowledgments stay outside persistence and undo.

## Limits and acceptance

The supported imported features, glTF color/sampler policy, payload/draw quotas and
centroid transparency approximation are unchanged from ADR 0074. Document-assigned
component images, unsupported legacy features, imported atlas/baking, file-preview
adoption and textured export remain separate acceptance work under #143. There
are no new dependencies, archive migrations or Qt links.

Tests cover actual imported generation/presentation state, stale frame/error
callbacks, replacement, stop/empty output, original error and exact retry snapshot,
plus edit/undo/redo and save/reopen with byte-exact original GLB assets. Existing
procedural material tests must remain green. Native app acceptance, full `make ci`,
exact-head automated review and every hosted check are required before merge.
