# ADR 0074: Imported material rendering in the standalone viewer

Status: implemented locally under #157; local full gate and scoped native acceptance pass; hosted review/CI pending.

## Decision and boundaries

Use the reviewed exact core pin and owned surface/material APIs from ADR 0073.
Join immutable source facts and material/image data from one archive snapshot on
a background actor. Keep byte-exact model/component identity semantics. No native
adapter or dependency is duplicated in the Apple repository.

Render imported authored UVs directly with per-model Metal samplers instead of
passing repeat coordinates into the existing normalized atlas path. The shared
renderer is reusable, but this delivery adopts it only in the viewer. The editor,
Quick Look/thumbnail services, imported atlas baking and export remain separate
M4 acceptance work; the full editor plan is not complete.

Linearize document fallback vertex RGB before interpolation; glTF COLOR_0 is
already linear. Upload source pixels as RGBA8 sRGB so RGB decoding precedes
filtering, including generated mips. Alpha stays linear and straight. Multiply
source RGB/alpha, texture samples and linear base factors; apply metallic,
roughness and emissive scalars. OPAQUE ignores alpha, MASK compares the product
against cutoff and writes opaque depth, BLEND preserves the product and disables
depth writes. Cull single-sided backfaces and flip backface normals for double-sided
surfaces. Unknown bridges/procedural faces retain source colors without invented
model/texture ownership.

Use the same PBR display calculation for baked and imported paths. This is not a
claim of Qt pixel parity: Qt's legacy GLB reader uses baseColorFactor only when no
image loads. The imported path follows the glTF multiplier/color policy. Imported
PNG decoding also preserves keyed transparent grayscale RGB, required when OPAQUE
ignores alpha; the separate Qt-compatible bake decoder keeps its previous policy.
See the [glTF specification](https://github.com/KhronosGroup/glTF/blob/main/specification/2.0/Specification.adoc#metallic-roughness-material).

## Ownership, admission and presentation

Transfer one fresh noncopyable GPU resource graph through Swift 6 `sending`, with
no unchecked Sendable escape. Actor scheduling serializes preparation; an explicitly
nonisolated synchronous factory builds the disconnected resource graph. Native
owners are already released before this stage. Close blit encoders on cancellation
and complete mip generation before publishing resources. Original Metal/native/
codec errors remain visible, and cancelled/stale outputs cannot replace a document.

Source/fact copy limits are independent. Decoded image storage defaults to 64 MiB
aggregate, with a 16 MiB per-encoded-image limit. Upload admission defaults/maxes
to 256 MiB for prepared vertex/triangle/material records, index payload and logical
texture/mip pixels. Bound device buffer sizes, 4096 imported materials and 4096
coalesced draw runs per opaque/blended pass. Quotas exclude scene-owned input data,
sort/codec/generator workspace, driver allocation overhead and in-flight replacement
buffers; they are not RSS or hard-time limits. Highly interleaved large scenes may
fall back to ordinary geometry after an orbit changes draw coalescing.

Sort blended triangles globally by rotated centroids before coalescing adjacent
model bindings. Intersecting/coplanar transparency remains approximate. Undefined
samplers use repeat wrapping, linear magnification and trilinear minification;
explicit glTF filters/wrap axes are retained. Supported images are bounded RGBA8
PNG/JPEG samples; original archive assets remain byte-exact and are not re-encoded.

Expose mutually exclusive baked/imported viewport content while preserving the
existing baked initializer. Keep view identity/camera across background adoption.
Only acknowledge a completed current GPU frame when changing compatibility notices.
Guard failed callbacks with the same current revision contract. Keep source/
procedural/unknown notices and ordinary geometry when optional material work fails.

## Acceptance

Pure tests cover geometry/corner/catalog alignment, finite/image/buffer limits,
exact quotas, sampler rules and global draw ordering. Actual production Metal
encoding tests cover source orientation, per-axis wrapping, linear filtering,
mip minification, factor/scalar shading, alpha modes, sidedness and wireframe.
Viewer/viewport tests cover cancellation, old results/failures, camera retention,
retry and original causes. Native UI, full make ci, screenshot and exact-head
review/hosted gates are required before merge; no full M4 parity is inferred.
