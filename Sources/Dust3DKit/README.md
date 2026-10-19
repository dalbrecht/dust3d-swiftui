# Dust3DKit

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
viewer now combines source facts/pixels with the shared imported PBR renderer;
editor and system-preview adoption remain pending. Geometry previews retain an explicit unapplied-material warning.
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
