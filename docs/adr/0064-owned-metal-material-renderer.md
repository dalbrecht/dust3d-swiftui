# ADR 0064: Owned Metal material renderer

Status: implemented locally, Apple #129; full local gate passed; automated review pending.
Four admission/order tests and nine real-Metal acceptance tests pass locally.

## Established boundary

After merged #128, immutable TexturedRenderGeometry supplies 80-byte GPU-layout
vertices and stable UInt32 indices without collapsing source/material seams.
BakedMetalUploadPlan validates combined logical geometry/texture payload, actual
device buffer spans, texture dimensions, readable padded rows and all map slots
before any Metal allocation. Color/emission upload as RGBA8 sRGB; normal and
scalar maps upload as linear RGBA8. Missing normal/metallic/roughness/emission
maps have explicit neutral defaults. Source profile normalization remains outside
this legacy RGB contract; wide-gamut color-management parity is not claimed.

BakedTriangleOrder retains opaque source order and sorts transparent triangle
centroids back-to-front after camera rotation. Mapped triangles route
conservatively to transparency if any atlas pixel has alpha below 255; unmapped
triangles use vertex alpha. Conservative routing can disable opaque depth writes
for opaque regions of a mixed-alpha atlas. This does not change their alpha;
centroid sorting still has intersecting/coplanar limitations and is not exact OIT.
Cancellation is checked during image scanning, triangle preparation and sorting.

## Verified Swift ownership approach

The actual Xcode SDK marks MTLDevice, command queues, pipelines, depth states and
samplers Sendable, but MTLBuffer/MTLTexture are non-Sendable. A standalone Swift 6
strict-concurrency probe rejects a purported Sendable resource aggregate. A second
probe successfully transfers freshly created buffers/textures with a `sending`
actor return, including a noncopyable owner stored by a main-actor class.

Use that verified boundary for background resource creation and uploads. Do not
add custom unchecked Sendable, preconcurrency suppression, or shared mutable
buffer aliases. The implemented owner is noncopyable; its freshly created buffers and
textures transfer once into the main-actor renderer. Pipeline states can cross the
actor boundary directly under their SDK Sendable contracts.

## Production implementation

- Actor resource builder: prepare CPU geometry, preflight upload plan, compile the
  material shader, allocate/upload buffers/maps and return a `sending` noncopyable
  owner. Use shared textures on unified-memory devices and managed textures on
  discrete devices; preserve platform allocation/compile errors. Keep immutable
  geometry/material resources after upload. Quotas exclude CPU source/workspace,
  device overhead and in-flight replacement buffers, not a hard RSS limit.
- Append the actual textured vertex/fragment pipeline to the packaged Metal
  source without changing the ordinary functions. Match five float4 vertex
  fields and uniforms containing transform, rotation, eye and map flags. Use a
  safe tangent basis, explicit missing UV/tangent flags, GGX direct material
  lighting, bounded roughness/metallic, emission and finite normalization.
- Blend straight alpha in a linear render pass with sRGB render targets, leaving
  encoding to hardware. Opaque draws write depth; transparent draws test depth
  without writing it. A zero-alpha fragment must not hide geometry behind it.
  Avoid display-encoded blending or double sRGB encoding.
- Main-actor TexturedMeshRenderer: encode the production material pass for MTKView
  and offscreen targets, preserve orbit/fit/wireframe semantics, and retain owned
  GPU resources. Initial sorting matches the initial camera. Rotation schedules
  background sort/index-buffer creation and a `sending` replacement. Superseded
  results cannot publish; preserve the previous order and original cause if
  derived ordering fails, then request redraw after successful replacement.
- Real-GPU tests: independent asymmetric atlas orientation, zero/low/partial alpha,
  ordering independent of source order at distinct depths, camera reordering,
  metal/roughness/emission/normal effects, neutral defaults, missing UV/tangent
  fallback and actual pinned-engine output. Reuse the production encoder. Skip
  explicitly only when there is no Metal device; optional local PNG evidence is
  not a committed snapshot baseline.

Existing viewport/app adoption follows the verified production pass. AO, embedded
models, import controls, exports, app scheduling/invalidation and broader M4/Qt
acceptance remain required by the full editor plan. This stage does not establish full Qt material or app parity. Full make ci passed with 600 tests. Automated review and all remote CI are
required before merge.
