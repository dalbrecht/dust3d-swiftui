# ADR 0082: Shared archive-material preparation

Status: Accepted

## Context

Selecting authored imported rendering whenever an imported model exists leaves
procedural image materials unbaked in mixed documents. The owned source-aware
baker and shared Metal renderer now support both kinds. Repeating selection in
each app and file-preview provider would allow policies and quotas to diverge.
Tracked in #172 as part of M4 (#143).

## Decision

A background `ArchiveMaterialPreparationService` in the shared rendering library
returns one immutable `MeshMaterialContent` from one unchanged archive snapshot.
Keep authored imported rendering when all retained triangles have model ownership;
use legacy baking when no imported model contributes; use source-aware baking
when an imported surface includes procedural/unknown-owned triangles. Unknown
bridges conservatively enter the mixed path. Headless SDK ownership stays in
Dust3DKit; no GPU resource or observable state enters preparation.

The service injects existing imported/procedural/source boundaries and forwards
selected-path quotas and original errors. Check cancellation before inspection,
after inspection and after baking. Mixed inspection returns a data-free decision
so its copied images can be released before the source baker repeats inspection
and decoding. This costs extra work but avoids retaining two decoded-image sets.
Independent workspace/output quotas are not a process-memory guarantee.

Adopt the service in the viewer first. Store one enum-valued material result and
derive representation-specific accessors. Preserve current-frame confirmation,
request/revision guards, stop, retry and ordinary geometry fallback. Mixed defaults
use atlas 256 and normal/material maps 256 so chart padding is representable in
every map, with color 512. Pure procedural defaults remain unchanged.

## Verification and remaining work

CPU tests cover all choices, quota forwarding, cancellation and original failures.
The synthetic MIT MixedMaterials archive preserves the original imported GLB,
adds a separate textured procedural surface, and retains an opaque asset.
Viewer lifecycle tests and native Metal tests use it without archive rewriting.
Native inspection displays both the teal imported and red procedural surfaces;
screenshots remain external diagnostics, not committed pixel baselines.

Editor and macOS file-preview adoption follow in separate reviewed stages.
Atlases remain base-level only pending core #59. Repeated mixed inspection is an
optimization opportunity; broader M4 parity, textured export and M5–M8 acceptance
are not completed by this change.
