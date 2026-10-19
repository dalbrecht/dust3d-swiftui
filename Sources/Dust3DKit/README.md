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
PNG preserves the existing bake decoder's source-sample policy. JPEG supports
8-bit sequential/progressive RGB and grayscale platform layouts; unsupported
layouts fail explicitly. Neither decoder applies EXIF orientation or material
factors. Synchronous native/codec work cannot be preempted; cancellation is checked
around work and at pixel row boundaries. Call synchronous APIs off the main actor.

Imported material facts and pixels do not yet imply UV, baking, PBR rendering or
export support. Geometry previews retain an explicit unapplied-material warning.
Archive edits preserve original assets rather than re-encoding image or GLB data.
Tests use real owned C handles and synthetic MIT fixtures, plus malformed/budget
cases. ImageIO remains a thin platform boundary; whole-engine coverage and Qt
render parity are not claimed by these tests.
