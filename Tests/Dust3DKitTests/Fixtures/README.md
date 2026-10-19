# Mesh loading fixtures

Capsule and Sword are existing MIT project fixtures. Capsule has three nodes and
one part; Sword comes from the inherited sword modeling example.

RoundedCrossing.ds3 is the synthetic MIT regression from dust3d-core issue #3,
independently encoded with Python on 2026-10-16. It contains five nodes, two parts
and three edges, with subdivision and rounded ends enabled. The previous pinned
core 685b68fb45405dabb4bb6f72c5b0e2598d4b9fdf fails to generate its mesh. Core
PR #4 fixes this case; the Swift regression checks successful complete loading,
finite positions/colors and unit normals within 0.001. Core tests additionally
check closed edge topology, translated/hard/subtraction variants and near-weld
separation; this Swift integration test does not prescribe triangulation order.

These binary archives have byte offsets and CRLF headers. Do not text-normalize.

ImportedMaterials.ds3 and ImportedPreview.ds3 are synthetic MIT fixtures encoded
independently with Python for Apple issue #153, consuming core revision
4db1bb770b4c342446805f77ccfa4dc0aabc90c4. The first checks two model materials,
original braced/bare identities, shared instances and an uninstanced part. The
second contains a closed tetrahedron on a two-node spine for geometry preview and
lossless edit/undo/reopen checks. Their GLB assets must remain byte-exact on save.

ImportedMaterial.png is the core's synthetic 2x2 straight-alpha RGBA fixture:
red/128 alpha, green/255, blue/255, yellow/64 in row order. ImportedMaterial.jpg
is the corresponding core-owned 2x2 JPEG. ImportedProgressive.jpg was generated
with jpegtran -progressive -copy none from that JPEG; ImportedGray.jpg was created
with cjpeg -grayscale -quality 95 from a synthetic 2x2 RGB PPM. These tools are
fixture-generation tools, not application dependencies. JPEG tests check shape,
opacity and grayscale relationships rather than codec-dependent exact RGB values.
ImportedCMYK.jpg is a synthetic 2x2 device-CMYK CGImage encoded by Apple's ImageIO
JPEG writer. Its unsupported CMYK pixel layout must produce a typed failure,
rather than silently interpreting four CMYK channels as RGBA.

ImportedSurface.ds3 is copied byte-for-byte from the synthetic MIT core #51
fixture at 0a83c3e3a59da4bafb5e3e83023fffd7df5cca90 (SHA-256
78d9e6a94cceccc4b5814692d25e8ca97ca01968c14927880a5e6a5837f715d6).
It derives from ImportedPreview.ds3 with independently authored normalized uint8
COLOR_0 values and alpha; its texture and nontrivial material factors remain
separate from source RGBA. The mirror test independently rebuilds its narrow DS3
envelope after changing XML, preserving original GLB bytes. It is not a rendered
baseline and carries no additional dependency or license requirement.
