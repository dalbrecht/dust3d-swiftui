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
dimensions could support hypothetical mipmaps. Opt-in native mip copying now binds the existing pinned accessors; broad GPU
and mixed-chart policy adoption remain separate. See ADR 0085 and #175.

`SourceBakedMesh.mipmaps` retains immutable optional chains by material role.
Existing base-only native loading leaves these empty; copied-output root accounting
includes the actual source-result layout. The shared renderer consumes result-owned
chains without a caller override. Set `SourceMeshBakeOptions(maximumMipLevels: 1...14)` to opt into
the pinned isolated mip baker and copy every returned level before owner destruction.
Zero remains base-only. Each level-zero view must alias the base accessor and each
chain validates the producer LOD; native/Swift byte quotas cover all retained levels.
This does not enable mixed-material rendering or establish chart ownership parity.
See ADR 0153 and #288.

`DocumentExportFileService(encoder:)` publishes an immutable current document
snapshot via an injected `DocumentExportEncoding` implementation. For example,
`try await service.export(document, format: .obj, to: output, sourceURL: source)`.
It preserves the source/savepoint and returns owned bytes with the diagnostic.
`NativeOBJExportEncoder()` binds original procedural OBJ output to the reviewed
pinned core ABI, copying bytes and warning before destroying the native owner.
The default output payload quota is 64 MiB; this is not an RSS/workspace bound.
OBJ exports no UVs, materials, imported models, rigs or animation.
The shared NativeGeometryExportEncoder routes OBJ and FBX for the editor. Cancellation
is checked before/after synchronous generation; it cannot interrupt native work.
See ADR 0118 and ADR0100 for destination and atomic-publication limits.


`NativeAnimationCatalogLoader().load()` copies the fixed document-free catalog
from the unchanged reviewed core pin. It returns owned `AnimationAuthoringCatalog`
values after destroying the native handle. Only names, declared timing, preset
values, controls and surface names are read; no animation/document is evaluated.
The actor rejects Swift cancellation before/after copy and preserves original
native errors. Collection caps and a 1 MiB logical host-copy quota count value
slots plus UTF-8 strings; they do not bound native catalog construction, temporary
validation allocations or process RSS. The existing static catalog smoke contract
provides the healthy ownership evidence; no foreign-pointer/fault/coarse-sampling
probes are added. See ADR 0119.


`NativeFBXExportEncoder()` binds only original procedural GEOMETRY mode at the
same core pin. It copies strict UTF-8 diagnostics and bytes before owner release,
with independent geometry/output logical quotas (64 MiB each by default, up to
256 MiB). Copied bytes plus warning share the output quota; warning text is at
most 4096 UTF-8 bytes. These are not workspace/time/RSS bounds. Original native
errors and before/after Swift cancellation survive without native interruption.
FBX retains static position/topology/corner streams supplied by the generator;
it does not request baking, imported assets, material, rig or animation output.
Use `NativeGeometryExportEncoder()` for explicit format routing without fallback.
See ADR 0121 and the scoped independent Assimp verification.

## Pinned rig template resources

`RigTemplateResources.data(forSourceType:)` returns owned, size/hash-verified XML bytes for the seven inherited templates. Absent, empty and `None` return nil; unknown types or missing/changed resources throw `RigTemplateResourceError`. Reads are bounded to 16 KiB plus one detection byte. Installed app/extension lookup uses only its packaged SDK bundle; CLI/tests use SwiftPM resources. `RigTemplates/provenance.json` records the exact core source revision and byte hashes, with the upstream MIT license. This API does not generate a skeleton or enable rig/pose evaluation.

`RigTemplateHierarchy.load(sourceType:)` exposes ordered names, parents and roots
from verified template resources. None returns nil; unsupported types and resource
failures retain their typed errors. Invalid/cyclic metadata rejects atomically.
This API performs no skeleton generation or pose evaluation.

Experimental template draw copies are available behind
`MOTE3D_EXPERIMENTAL_RIG_TEMPLATE` in isolated local-core builds. `RigTemplateMesh`
returns owned Swift vertices and exact source-order names, retaining flat normals
and semantic bone/selected/ring roles. It does not create a document rig or pose.
Run its synchronous loader off the main actor. See ADR0160 for quotas, identity
and validation limits. The production core revision remains unchanged.

## Experimental actual generated rigs

`MOTE3D_EXPERIMENTAL_GENERATED_RIG` enables `GeneratedRigService` against a local
core containing the generated-rig C ABI (core330, e63d16f0). The separate flag does
not change template-only experiments or the production pin. Pass immutable archive
bytes and a pinned rig type; the actor returns copied Sendable mesh, exact source
joints/parents, column-major rest/inverse arrays and all four draw-corner weights.
None returns nil; original resource/native errors remain visible. Cancellation
uses a lock-backed native token and Swift checkpoints, without a fixed-latency
promise for every inherited stage. No native handle escapes into Swift results.

The data does not evaluate poses/animation or expose a complete UV/export model.
A future preview must use the returned grounded body with its own joints, capture
document identity/revision/bytes/settings and reject stale requests. Ordinary mesh
geometry identity does not advance for rig-only edits. See ADR0161.
