# Shared Metal rendering

Internal SwiftPM target used by the separate viewer and editor executables.
`MeshViewport` bridges SwiftUI to a main-actor MTKView; it copies validated mesh
buffers into Metal and loads Shaders.metal from this target’s resource bundle.

Supply a mesh, wireframe flag, camera-reset counter and an error callback.
Increment `meshRevision` when replacing geometry to retain the orbit camera;
change `cameraReset` to fit again. The viewer recreates its viewport on file open.

Build with `make ci`; package with `script/build_and_run.sh --build-only` or
`--editor --build-only`. GPU interaction remains a manual verification boundary.

Camera fitting uses the narrower viewport axis around the normalized mesh bounds.
Resizing preserves orbit and relative zoom; Fit resets both. Both depth planes follow
the fitted distance to preserve depth precision for very narrow viewports. `Dust3DRenderingTests` covers the
pure camera at 100% line coverage, including a real disjoint-sphere core mesh.
This does not measure Metal draw or native input coverage.

Both apps supply `IndexedMesh`: the renderer uploads unique vertices plus a UInt32
index buffer and uses indexed triangle draws. The existing `MeshViewport(mesh: Mesh, ...)`
initializer keeps expanded callers compatible. Pure `RenderGeometry` validates
triangle buffers and normalizes bounds, then checks actual GPU-layout byte lengths
against the device buffer limit before GPU allocation. `MeshRenderer.encode`
is shared by drawable presentation and offscreen GPU verification.

`IndexedMetalRenderingTests` compares solid/wireframe indexed output with expanded
output on the same device. It explicitly skips when no Metal device exists.
Set `DUST3D_METAL_QA_OUTPUT_DIR` to write optional local evidence PNGs; these are not
committed visual baselines. Interactive window/input verification remains separate.

`TexturedRenderGeometry` is an internal, immutable Sendable preparation value for
subsequent baked-material renderer adoption. It retains copied SDK maps/metadata
and creates stable UInt32 indices with complete position/normal/color, UV, tangent,
mapping and component seams. Shared `RenderBounds` keeps ordinary/textured camera
normalization identical. Prepare outside the main actor; validate actual buffer
lengths against the device limit before upload. Logical output quotas exclude
source arrays, metadata/textures and indexing workspace. The baked-material encoder uses this representation in both native app
viewports, with ordinary previews retained during baking and on optional failure. See ADR 0063 and
`docs/textured-render-geometry-verification.md` for tests and remaining integration.

`TexturedMetalResourcesBuilder` performs preparation, admission and uploads on an
actor and transfers fresh noncopyable GPU ownership into `TexturedMeshRenderer`.
The encoder consumes color/normal/metallic/roughness/emission maps, blends linear
straight alpha into BGRA8 sRGB, writes opaque depth and sorts transparent
triangles after camera rotation. `TexturedMetalRenderingTests` exercises this
production pass on a real Metal device, including pinned-core baked output.
See ADR 0064 and `docs/metal-material-renderer-verification.md` for measured
coverage, conservative transparency routing and remaining app/material limits.

Supply `bakedMesh` paired with `meshRevision` to adopt materials asynchronously.
Use `onMaterialError` for optional diagnostics (defaults to `onError`). The view
retains orbit/zoom/fit/wireframe, rejects obsolete uploads and cancels detached
work. Both ordinary and material resources can coexist for fallback; quotas do
not claim a whole-process memory cap. See ADR 0065 and native material viewport
verification for app lifecycle and acceptance evidence.

## macOS file previews

`FilePreviewDocumentService` loads one bounded archive snapshot without writing
the file. `FilePreviewRenderer` uses the shared production Metal encoder for
transparent thumbnail output; `FilePreviewView` hosts read-only interactive
Quick Look content. The editor packages the two system providers. See
[ADR 0066](../../docs/adr/0066-macos-file-preview-extensions.md) for quotas,
registration, sandboxing and supported-content limits.

## Build diagnostics

The About window reports the source revision/digest, dirty state and exact core pin
embedded in the loaded executable, separately from process identity. The startup
capture remains fixed if an on-disk bundle changes. Use the canonical build wrapper
to embed metadata; direct SwiftPM builds show unavailable identity honestly.
See [ADR 0071](../../docs/adr/0071-immutable-runtime-build-identity.md).

## Imported model materials

`MeshViewport(..., materials: .imported(inputs), ...)` accepts coherent
`ImportedMaterialRenderData`; `.baked` retains the existing atlas representation.
The enum prevents mixing representations, and the original `bakedMesh` initializer
remains compatible. Keep the same view identity and increment meshRevision for
new output/retries; orbit/zoom survive background adoption. Acknowledgment follows
a current completed GPU frame, not just resource upload. Revision checks reject
obsolete failures as well as successes.

Pure imported geometry/sampler/image/draw plans validate finite values, catalog
alignment, actual device-buffer lengths, logical mip/vertex/index payloads,
4096 material entries and 4096 draw runs per pass before submission. The actor
builds one fresh noncopyable GPU ownership graph and transfers it with `sending`;
there are no unchecked Sendable declarations. Texture storage is RGBA8 sRGB,
vertex RGB is linear before interpolation, and factor/alpha/culling policy is
per model. Both imported and baked encoders use the same PBR display calculation.
Unknown bridges retain source colors without invented texture ownership.

Hardware tests verify orientation, wrapping, straight alpha policies, globally
sorted cross-model transparency, scalar PBR factors, wireframe/culling,
linear-space filtering and minification against independent factor references.
Tests explicitly skip if Metal is unavailable; native inspection remains separate.
The editor and file-preview services also use this authored imported path. See
ADR 0074 and imported-material viewer verification for its semantics.

System file previews prepare mutually exclusive baked/imported materials from the
same read-only archive snapshot. Imported thumbnail rendering reuses the production
encoder, 64 MiB logical upload admission, fitted camera and premultiplied-sRGB
readback. Preparation failures retain ordinary geometry and their original cause;
thumbnail GPU failures return the original system error. See
[ADR 0076](../../docs/adr/0076-imported-material-file-previews.md) for quotas and
native-host acceptance requirements.

## Source-baked materials

`MeshViewport(..., materials: .sourceBaked(output), ...)` consumes owned
`SourceBakedMesh` values from the source-aware SDK/archive service. Retain the
original indexed geometry as fallback, keep the same view identity, and advance
`meshRevision` for replacement output or retry. The existing legacy `.baked` and
authored `.imported` representations retain their behavior. App preparation still
chooses its existing representations until separate source-bake adoption.

Source and legacy bakes share one seam-safe indexer, resource builder and Metal
encoder. Source metadata keeps actual packed triangles and exact model/component
catalogs, without fabricated legacy UV charts. Model and component memberships
participate in corner sharing. UVs, tangents, references, policy and atlas LOD are
validated before upload; vertex/index quotas count logical arrays, excluding
retained source metadata, indexing workspace and allocator/driver overhead.

Opaque and mask triangles write depth. Masks apply the authored cutoff, including
zero, and accepted fragments are opaque. Blend triangles sort globally by camera
depth; adjacent identical policies coalesce into draw runs. There is a 4096-run
limit per pass. Culling follows sidedness; unknown policy retains the conservative
legacy path. Unknown mappings use geometry colors and ignore atlas samples.
Camera replacements move sorted indices and matching policy runs together; stale
uploads/callbacks and detached views cannot publish a new material frame.

`maximumSamplingLod` is preserved and bounds the atlas sampler. Current uploads
contain only the base level and explicitly disable mip filtering. They never
generate a mixed-chart mip chain; chart-isolated mipmaps remain core issue #59.
Mapped colors/factors are already in the baked maps, so the shader applies them
once. Color/emission textures use sRGB formats; normal/scalar maps use linear data.

Native GPU contracts cover alpha modes/cutoffs, sidedness, masked depth, globally
sorted mixed policies after camera changes, unmapped fallback and actual source
bakes, alongside the legacy regression suite. Tests skip explicitly without a
Metal device. Offscreen PNGs are diagnostic artifacts, not committed pixel
baselines or a claim of full application/material parity. See ADR 0079 and #167.

Alpha cutoffs retain their original finite nonnegative Double metadata. The GPU
threshold rounds upward to preserve comparisons against available Float alpha
samples; a separate flag excludes zero for positive cutoffs even when subnormal
thresholds flush to zero. Cutoffs above one reject every mask fragment. Opaque
and blend policies ignore the cutoff. This does not add 64-bit texture or material
math or remove existing bake quantization. See ADR 0080 and #169.

`ArchiveMaterialPreparationService` prepares one `MeshMaterialContent` from one
unchanged archive: authored imported for all-owned imported triangles, legacy
baked when there is no rendered imported model, and source-baked when retained
imported geometry also contains procedural/unknown-owned triangles. Selected-path
quotas are explicit in `ArchiveMaterialPreparationOptions`. Original errors and
cancellation propagate; callers own revision checks and ordinary geometry fallback.
Selection inspects source geometry without copying/decoding material images,
using independent `selectionSurface` limits. Its geometry owner is released before
the selected path enforces its own image policy and performs decoding. There is no retained document cache or GPU state in this actor.
The viewer adopts it first; editor/file-preview adoption is separate (#172, ADR 0082).

File previews use the same archive preparation service with explicit preview quotas.
Thumbnail dispatch supports legacy, authored imported and source-baked materials;
CPU-tested fallback preserves original causes and cancellation. Fully transparent
material output is valid. See ADR 0084 and the mixed file-preview verification record.
