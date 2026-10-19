# ADR 0079: Shared source-baked Metal rendering

Status: Accepted for implementation; issue #167, M4 issue #143.

Extend MeshMaterialContent with sourceBaked while retaining the original indexed
mesh for optional failure fallback. Reuse the existing textured geometry indexer,
resource ownership builder, encoder and viewport upload lifecycle. Keep the
authored imported renderer available; do not introduce another independent Metal
renderer or modify current application material preparation in this foundation.

Use an explicit legacy/source metadata enum. Source metadata retains actual packed
triangle records and exact model/component catalogs rather than pretending to be
a legacy UV chart result. Include model membership in corner keys alongside
position/normal/color, exact UV bits, tangent frame, mapping and component identity.
Validate source references, policy, UVs, tangent applicability and the all-map LOD
bound before upload. Vertex/index quotas count logical arrays; source metadata,
temporary indexing, allocator/driver overhead and replacement buffers remain
outside that GPU admission budget.

Preserve per-triangle alpha and sidedness. Opaque and mask use the depth-writing
pass; mask compares raw combined alpha with the cutoff, then makes accepted
fragments opaque. A zero cutoff accepts zero alpha as the material contract
requires. Blend uses global camera-depth sorting and no depth writes. Coalesce
only adjacent identical policy runs after sorting, bound runs to 4096 per pass,
and transfer replacement indices and policy runs atomically on the main actor.
Use explicit back-face culling for single-sided sources. Unknown policy keeps
legacy conservative alpha/sidedness; unmapped triangles keep geometry-color
fallback without invented source material ownership.

Source maps already contain material/source factors, and mapped native vertices
are neutral. Sample sRGB color/emission and linear normal/scalars through the
existing PBR display calculation without multiplying source factors again. Carry
maximumSamplingLod into the atlas sampler. At present all uploads contain a single
base level with mip filtering disabled. Do not generate a global mixed-chart mip
chain; core #59 and a future owned mip-level ABI are separate work.

Keep CPU preparation and Metal allocation in the builder actor, returning fresh
noncopyable resources through sending. UI presentation and revisions stay on the
main actor. Source and legacy uploads use the same camera preservation, current
frame acknowledgment, cancellation and fallback logic. Original errors remain
actionable, including source metadata/LOD and draw-run limits.

Verify actual imported/procedural source bakes through the production offscreen
encoder, independent alpha/culling/depth samples, mixed policy camera reordering,
model seams, exact logical limits, metadata defenses and viewport replacement.
Retain all legacy rendering regressions. Hardware tests explicitly skip without
Metal; artifacts are diagnostic PNGs rather than locally generated pixel baselines.
Run the full local gate and automated/hosted review before merge. App source-bake
preparation adoption, textured export, chart-isolated mipmaps, broader material
compatibility and full M4–M8 acceptance remain open.
