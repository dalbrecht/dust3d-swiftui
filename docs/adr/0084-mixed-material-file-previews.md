# ADR 0084: Mixed-material macOS file previews

Status: Accepted for implementation; public review pending. Related: #174, ADR 0082.

## Context

Viewer and editor material preparation now distinguish procedural, authored imported,
and mixed source-baked surfaces. File previews must make the same choice from one
unchanged archive, without dropping procedural surfaces or requiring a save.

## Decision

FilePreviewDocumentService uses ArchiveMaterialPreparationService with explicit
preview quotas. Source baking uses 512/256/256 maps and a 256 atlas, with 32 MiB
bake, sampler and atlas budgets, 64 MiB native output and Swift copy budgets, and
64 MiB decoded image input. Image encoding limits remain 16 MiB per image and
32 MiB total. These are layered payload limits, not a process RSS guarantee.

Interactive Quick Look consumes the prepared material enum through the shared
viewport. Thumbnails dispatch every representation through FilePreviewRenderer.
Source and legacy textured uploads share the existing encoder with an explicit
64 MiB payload budget; application defaults retain their existing budget.

A pure orchestration policy preserves ordinary geometry after optional material
failure, retains the original cause, and preserves both causes when fallback also
fails. Cancellation prevents additional fallback work and stale publication.
Successful fully transparent materials remain transparent. Confirmed source-baked
frames clear recognized surface-detail limitations, while fallback restores the
original compatibility notice. Provider logs include
an operation identifier and private original failure description. Source bake
errors now expose specific localized diagnostics while retaining typed identity.

## Verification and limits

See [native and automated evidence](../mixed-file-preview-verification.md).
No new dependencies, provider identifiers, or signing requirements are introduced.
Chart-isolated mipmaps (core #59), large-model atlas acceptance, additional format
coverage and textured export remain separate work. This is not complete M4 parity.
