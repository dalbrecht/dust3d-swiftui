# Native Dust3D viewer

Standalone SwiftUI/Metal macOS app for opening existing `.ds3` documents without
Qt. Build/run with `./script/build_and_run.sh`; validate with `make ci`. The root
SwiftPM manifest defines all dependencies; no separate Xcode project or runtime
configuration is required.

Open a document with the toolbar or File menu. Drag to orbit, scroll to zoom,
use Fit Model to reset the camera, and toggle Wireframe to inspect triangles.
Ordinary geometry appears before background material preparation. Procedural
color/normal/metallic/roughness/emission maps use bounded bake resolution. Imported
GLB previews use authored UVs, PNG/JPEG source pixels, per-model filters/wrapping,
linear factors and vertex RGB, metallic/roughness/emissive scalars, opaque/mask/blend
alpha and double-sided policy. Unsupported core GLB features fail explicitly.


A single bounded file snapshot supplies geometry and baking, so a later file
change cannot mix old geometry with new assets. Optional material failures keep
ordinary geometry and show the original diagnostic with Retry Materials. Closing
the view cancels pending work; late results cannot restore a closed preview.

See `docs/native-material-viewports-verification.md` and ADR 0065 for tests,
native acceptance and remaining AO, transparency and full-parity limits.

Compatibility notices follow the representation being displayed: successful image
baking removes obsolete untextured-image text; geometry/GPU fallback restores its
original notice. Legacy surface limitations and source interpretation failures
remain explicit. Metadata is prepared from the same file snapshot off-main.

## Build diagnostics

The About window reports the source revision/digest, dirty state and exact core pin
embedded in the loaded executable, separately from process identity. The startup
capture remains fixed if an on-disk bundle changes. Use the canonical build wrapper
to embed metadata; direct SwiftPM builds show unavailable identity honestly.
See [ADR 0071](../../docs/adr/0071-immutable-runtime-build-identity.md).

## Imported material previews

Imported source UVs may repeat outside 0–1; they are not repacked atlas coordinates.
The viewer uploads sRGB source textures, filters in linear space, and retains
straight alpha until blending into an sRGB target. Unspecified filters use linear
magnification/trilinear minification with repeat wrapping. Global centroid sorting
handles blended model layers; intersecting/coplanar transparency remains approximate.

The imported path admits a 256 MiB logical upload budget, at most 4096 imported
material entries and 4096 coalesced draw runs in each pass. Exceeding a preview
resource limit keeps ordinary geometry and its diagnostic; it does not modify the
archive. Logical quotas exclude driver overhead, source/workspace and in-flight
replacement resources. A known imported-material limitation disappears only after
the current GPU frame succeeds; procedural/unknown limitations remain explicit.

This viewer stage does not add imported atlas baking, textured exports, editor
material display or material-aware system file previews. It deliberately applies
glTF factors even with a base-color image; Qt's legacy importer omits that factor
when an image loads. See [ADR 0074](../../docs/adr/0074-imported-material-viewer.md)
and [verification](../../docs/imported-material-viewer-verification.md).

Material preparation chooses one representation from the exact opened archive:
authored UV/sampler rendering for purely imported surfaces, legacy baking for
procedural-only geometry, and source-aware baking when imported and procedural
(or unknown bridge) triangles coexist. Imported and procedural textures therefore
share the mixed atlas while preserving per-triangle source alpha/sidedness.
Materials appear only for the matching current revision; replacement, cancellation,
GPU failure and retry retain ordinary geometry and original failure diagnostics.
The viewer never re-encodes the input archive.

The shared `ArchiveMaterialPreparationService` owns this choice. Mixed preparation
releases imported inspection output before re-inspecting the same bytes through
the source baker; this currently repeats inspection/decoding work. Default mixed
maps are color 512, normal/material 256, atlas 256, with 64 MiB aggregate decoded
image admission. Native/output/workspace quotas remain independent; these are not
a process-memory cap. Atlases currently sample only their base level (core #59).
Editor and system-preview adoption follow separately. See ADR 0082 and #172.
