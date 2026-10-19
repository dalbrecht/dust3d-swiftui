# ADR 0077: Owned source-aware Swift baking

Status: Accepted for implementation; issue #163, M4 issue #143.

Adopt the merged core source-bake API through exact revision
`c1215f472bd45b1ac4682c7d4c82be1e64064ee9` and committed `Package.resolved`.
Keep native sampler, source-atlas and composition implementations in dust3d-core;
do not recreate them in Swift or modify the inherited Qt reference application.
No new package dependency is added.

Expose immutable Sendable source-baked geometry, per-triangle optional UV/policy,
tangents, exact model/component catalogs and owned texture bytes. Preserve the
native maximum sampling LOD rather than inventing a Swift mip policy. At present
the clamp is zero pending chart-isolated mipmaps in core #59. Neutral mapped
vertex colors prevent factors being applied twice. Optional bake failure must
eventually fall back to the original ordinary/source mesh, not neutral baked colors.

Require caller-decoded source-matched RGBA8 inputs. Reuse ImportedImageDecoder
output through a convenience initializer; automatic archive image preparation and
renderer/export adoption are subsequent stages. Exact UTF-8 identity bytes avoid
Swift canonical-equivalence collisions. Validate dimensions, row spans, duplicate
keys, quotas and checked conversions before calling native code. Bound combined
actual decoded storage before NSData bridging. Immutable NSData pins pixels and
non-NUL-terminated identity spans throughout the synchronous call.

Copy all borrowed output before destroying the native owner. Validate counts,
catalog references, UVs, tangent frames, policy and sampling LOD before publication.
Independent Swift retained-output accounting bounds array capacities and copied
pixels. Logical quotas exclude temporary workspace and allocator overhead; they
are not hard RSS/CPU limits. Native generation errors retain their original status
and diagnostic. Swift boundary violations have typed SourceMeshBakeError values.

A background actor reuses the existing lock-protected native cancellation owner.
No new unchecked Sendable conformance is introduced. The token stays alive until
the operation and copy finish. Cancellation is checked after an operation returns,
so even an otherwise successful cancelled operation cannot publish output.

Verify real procedural/imported archives, independent lifetimes, exact copy quotas,
material factors/policy, malformed borrowed record defenses and active cancellation.
Run the full native gate, automated review and hosted checks before merge. No app
UI or archive serialization behavior changes in this stage; full M4 acceptance,
broader material semantics, renderer adoption and textured export remain open.
