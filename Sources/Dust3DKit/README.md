# Dust3DKit

`WorkerRequestEncoder.encode(archive:identity:operation:limits:)` copies base/UV
wire requests from the core codec into Sendable frame/header values. Call it off
the UI actor; it neither parses archive bytes nor launches a helper. Use
parent-owned `WorkerRequestIdentity` and positive `WorkerRequestLimits`; original
core errors retain numeric fields and diagnostic bytes. Logical quotas are not
process-memory bounds. See [ADR 0117](../../docs/adr/0117-owned-swift-worker-requests.md).

Typed Swift ownership boundary for the pinned Qt-free Dust3D core. Consumed as a
local SwiftPM library by the viewer, editor, rendering and preview targets. Build
with `make build` and run the native gate with `make ci` from the repository root.
No additional installation or runtime configuration is required.

`MeshLoader` copies generated geometry. `ImportedMaterialLoader` copies required
embedded model factors, samplers, bindings and encoded image bytes before releasing
the C owner. `ImportedMaterialService` serializes background inspection and image
decoding. Await `service.load(data: archive)` then
`service.decodeImage(image, modelID: material.id)` for independent RGBA8 samples.

Native and Swift output quotas are configurable logical ownership budgets, not
process RSS limits. Temporary indexes, allocator overhead and codec workspace are
excluded. Images have bounded encoded input, dimensions and final RGBA storage.
Imported PNG decoding preserves hidden keyed-grayscale RGB, needed when glTF ignores alpha; the separate legacy bake decoder keeps its Qt-compatible policy. JPEG supports
8-bit sequential/progressive RGB and grayscale platform layouts; unsupported
layouts fail explicitly. Neither decoder applies EXIF orientation or material
factors. Synchronous native/codec work cannot be preempted; cancellation is checked
around work and at pixel row boundaries. Call synchronous APIs off the main actor.

Imported inspection APIs remain separate from packed UV/baking and export. The
viewer, editor and system previews combine source facts/pixels with the shared
imported PBR renderer. Ordinary geometry previews retain an explicit unapplied-material warning.
Archive edits preserve original assets rather than re-encoding image or GLB data.
Tests use real owned C handles and synthetic MIT fixtures, plus malformed/budget
cases. ImageIO remains a thin platform boundary; whole-engine coverage and Qt
render parity are not claimed by these tests.

`ImportedSurfaceLoader.load(data: archive)` copies generated geometry and aligned
source UV/RGBA records from one owned core result. Await
`ImportedSurfaceService().load(data: archive)` for background work. Optional UVs
retain authored coordinates outside 0–1; nil means unmapped. Model/component
catalog indices remain bounded and optional, with original/generated membership
separate from Boolean provenance. RGB encoding is explicit; alpha is straight and
independent of material factors, textures and opaque preview policy.

The default native and Swift budgets are independently 64 MiB, with a 256 MiB
maximum. Swift charges records, array capacities, copied identity byte lengths
and warning bytes, excluding temporary lookup structures and allocator overhead.
No borrowed native pointer survives the load. Errors preserve original native
status/messages or provide typed Swift validation diagnostics. Cancellation is
checked around synchronous native work and between copied records. Source values
are not packed atlas UVs and do not enable imported texture display by themselves.

Surface model and component catalogs expose `ImportedSurfaceIdentity`, whose equality and
hashing compare UTF-8 bytes. Use `try ImportedSurfaceIdentity(rawValue: material.id)`
when correlating a material identity; read `.rawValue` for display or serialization.
This prevents Swift Unicode normalization from collapsing distinct engine keys.
The direct synchronous copy also checks cancellation after geometry allocation
and before returning, independently of the background service's publication check.

Component `.id` values use the same typed key as the model catalog. Convert an
unwrapped legacy `ImportedMaterialBinding.componentID` with
`try ImportedSurfaceIdentity(rawValue: componentID)` before dictionary lookup;
`.rawValue` is for presentation/serialization, not key comparison.

`ArchiveImportedMaterialService().loadIfPresent(data: archive, limits: .init())`
prepares coherent source geometry, byte-exact model/material joins and decoded
images from one immutable archive snapshot. Nil selects the existing procedural
bake path. Source/fact native and Swift quotas remain independent; decoded images
share a 64 MiB aggregate default and 16 MiB per-encoded-image limit, each at most
256 MiB. Codec/generator workspace and temporary lookups are excluded. Original
native/codec causes and cancellation survive; no source pixel is premultiplied or
modulated by factors during preparation. See ADR 0074 for renderer semantics.

## Source-aware baking

`MeshLoader.loadSourceBaked(data:modelImages:images:options:)` uses reviewed core
revision `41af7d4c1b67dd037e02858e3ef0fdb96a84aebb`. Call it off the main actor,
or await `SourceMeshBakingService().load(...)`. Pass `SourceMeshBakeImage` values
decoded from the same archive's imported material images; the convenience
`init(decodedImage:)` preserves `ImportedImageDecoder` output. Procedural images
use the existing `MeshBakeImage` identity convention. This low-level API cannot
prove that caller-supplied pixels correspond to the archive's encoded image.

The result owns expanded geometry, aligned packed UV/tangent/material-policy
records, exact identity catalogs and RGBA8 color/normal/scalar/emission maps.
Known mapped vertex colors are neutral because material/source factors are already
in the maps. Unknown UV/policy values remain optional. Copies finish before native
owner destruction. Source-aware baking does not rewrite the input archive.

Honor `maximumSamplingLod` on the output atlas: it is currently zero. Do not
generate a global mixed-chart mip chain; chart-isolated output mipmaps remain
tracked in `dalbrecht/dust3d-core#59`. Source-image derivative mip sampling is
independent. Insufficient map resolution to reserve chart padding fails explicitly.

`SourceMeshBakeOptions` defaults to 64 MiB each for native sampler/atlas storage,
256 MiB each for native and Swift retained output, and 64 MiB combined decoded
input storage. Each byte quota has a 256 MiB maximum. Actual input `Data.count`
includes row padding and trailing storage, and is checked before pixel bridging.
Swift output accounting includes array capacities, identity/warning bytes and
copied pixels; temporary lookup tables, allocator overhead and native workspace
are excluded. Chart/raster quotas bound packing inputs and pixel work, not total
generator CPU time or process RSS. Cancellation reaches the core token and is
checked again before publishing completed output.

This SDK foundation does not change the apps' rendering path, add textured export,
or establish full material compatibility. See ADR 0077 and issue #163.

`ArchiveSourceTextureBakingService().load(data:options:limits:)` prepares the
source-aware inputs from the same immutable archive before baking. It resolves
referenced procedural PNGs and declared required imported PNG/JPEG images, using
the existing decoders and their distinct source-alpha policies. A textureless
imported model requires no decoded pixels. This opt-in service does not modify
the current apps' material preparation/rendering paths.

`ArchiveSourceTextureLimits.materials` bounds native and Swift material inspection
copies, including encoded image storage. `.textures` admits combined encoded bytes
before pixel decoding (32 MiB per image, 128 MiB aggregate by default). Decoded
pixels share the smaller of `.textures.maximumDecodedTotalBytes` and
`SourceMeshBakeOptions.maximumInputImageBytes` (both 64 MiB by default).
All limits are logical budgets, with a 256 MiB ceiling per byte quota, separate
from codec/native workspace and input archive storage. Inspection itself precedes
combined encoded admission and remains independently bounded.

Procedural image failures retain ArchiveTextureBakingError asset context.
Imported image failures retain the exact model identity and original typed codec
error in ArchiveSourceTextureBakingError. Native/document failures and cancellation
propagate. Output is checked for cancellation after preparation and after baking.
Consumers must preserve the result's maximumSamplingLod and retain their original
geometry when an optional bake fails. See ADR 0078 and issue #165.

`TextureMipChain` validates owned base/additional levels and the producer-supplied
sampling cap. Checked copying preserves original accessor failures and cancellation,
charges aggregate copied/native bytes, and shares its image primitive with the
current source-bake path. Base-only loading rejects positive LOD even if image
dimensions could support hypothetical mipmaps. Actual native mip accessors and GPU
adoption await the reviewed core upgrade; see ADR 0085 and #175.

`SourceBakedMesh.mipmaps` retains immutable optional chains by material role.
Existing base-only native loading leaves these empty; copied-output root accounting
includes the actual source-result layout. The shared renderer consumes result-owned
chains without a caller override. Native count/level binding and generation await
the reviewed core upgrade; see ADR 0087 and #177.

`DocumentExportFileService(encoder:)` publishes an immutable current document
snapshot via an injected `DocumentExportEncoding` implementation. For example,
`try await service.export(document, format: .obj, to: output, sourceURL: source)`.
It preserves the source/savepoint and returns owned bytes with the diagnostic.
There is no production encoder binding until the core dependency is reviewed;
see ADR0100 for destination, cancellation and atomic-publication limits.
