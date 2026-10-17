# ADR 0052: Copied indexed meshes at the Swift boundary

Status: accepted

## Context

Core PR #18 adds independently owned indexed buffers. Passing native pointers into
Swift concurrency or the renderer would couple buffer lifetime to C handles.
Changing the existing expanded `Mesh` contract would also combine ownership and
renderer changes in one review.

## Decision

Pin core revision `50c41f131b6bfdf03bcda1ce0dc060de3b093169`. Add a distinct immutable
Sendable `IndexedMesh`, with copied position/normal/color vertices, UInt32 indices,
source counts and warnings. Keep expanded loading and rendering compatible.

The expanded native handle lives only through indexed conversion. Release it
before copying indexed buffers, then release the indexed owner after every value
has been copied. A shared scoped loader preserves existing error diagnostics.
Negative Swift budgets fail before crossing the size_t boundary. Zero selects the
core's 256 MiB exported-payload default; this is not a total memory ceiling.

Optional loading catches only successful no-geometry status 5. Budget, malformed
input and precision failures retain their status and cause.

## Consequences

Swift consumers cannot outlive borrowed buffers because none escape. This adds
no dependency or renderer change. Core still temporarily generates expanded
geometry and deduplication workspace; large-model peak memory and indexed GPU
adoption remain separate work. Source IDs, UVs and rigging attributes are absent.
