# ADR 0063: Seam-aware textured render geometry

Status: full local gate passes; automated review/remote CI pending, Apple #127.

## Decision

Add an internal immutable Sendable TexturedRenderGeometry preparation value to the
shared rendering target. It consumes the owned baked SDK result and retains its
UV/component metadata and texture maps by value. Preparation is pure CPU work;
future renderer integration must perform it outside the main actor before GPU
upload. Existing viewport initializers and shaders remain unchanged in this stage.

Each GPU-layout vertex contains normalized position, normal, color, atlas UVs,
explicit UV/tangent applicability and tangent direction/handedness. Stable UInt32
indices retain original triangle order. Share only complete, byte-exact source
corner keys: original position/normal/color, Double UV samples, tangent frame,
both mapping flags, component kind and bounded component identity index. The
metadata table already preserves byte-exact engine identities. Unknown, ambiguous
and future source kinds remain distinct. Using only position/normal/color, or
quantizing UVs before indexing, would merge source seams. Per-triangle component
metadata remains aligned with the indexed triangle stream.

Extract the existing ordinary bounds calculation into shared RenderBounds so both
render paths use identical camera normalization. Ordinary geometry, camera and
shader behavior retain their existing contracts and regression tests.

## Limits and errors

Require nonempty triangle-aligned finite geometry, matching UV/tangent counts,
finite tangent frames, valid handedness and normalized applicable tangents. A
mapped tangent requires an applicable UV triangle. Existing MeshUvMetadata already
validates source coordinates and component references at its construction boundary.

Before array allocation, validate the index span against a configurable positive
logical output quota (maximum/default 256 MiB). Before every unique vertex append,
charge its actual GPU-layout stride and perform checked UInt32 conversion. Separate
device-limit validation checks both actual vertex and index buffer byte lengths.
The quota excludes source SDK arrays, retained texture/metadata storage, dictionary
workspace and allocator capacity/overhead; it is not a process RSS cap. Cancellation
is cooperative at triangle boundaries. No Metal object is created by preparation.

## Evidence and subsequent adoption

Failing-first tests establish the absent preparation API. Targeted tests cover
stable sharing, position/normal/color/UV/tangent/handedness/material/mapping seams,
sub-Float UV distinctions, unknown/ambiguous/future component kinds, malformed
geometry/tangents, exact logical budgets, vertex/index-dominated device limits,
cancellation and actual pinned-engine baked output. Existing ordinary geometry
tests verify the shared bounds refactor. Full make ci passes (587 tests); measured pure preparation coverage is 98/98
lines, with shared ordinary preparation 69/69. Automated PR review and remote CI
remain required; see the stage verification report.

This is the render-data foundation, not a claim that apps display baked materials.
Production Metal texture upload/shading, transparent ordering, PBR/AO, asynchronous
app scheduling/invalidation and textured exports remain subsequent work in M4.
No external dependency or alternate native/core adapter is introduced.
