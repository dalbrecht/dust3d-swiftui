# Wrapping controller verification

Apple issue #100; ADR 0050. Exact core pin:
`4e49670e6819f996ddac1a2befb6f23d72154341` (reviewed core PR #15).

The new controller tests first failed to compile because the four methods were
absent. Real actor/controller tests now cover mode, keep-children, face counts and
all seven scalar drafts with actual pinned-core generation. Supported comma
values succeed. Invalid/unknown/nonfinite/out-of-range/underflow drafts and
non-group/missing owners retain document bytes, redo, preview revision and
publication count. Stopped stores perform no edit or draft error publication.

A synthetic one-sphere group fixture in Support/WrappingFixture.swift is authored
MIT test data, independently serialized with an opaque asset and comment. It has
one node at (.5,.5,.5), radius .2, and 64 target faces. Save publication bytes
round-trip, nodes/assets survive edits, selected group and camera remain stable,
and undo/redo restore exact bytes. Preview checks use finite positions, positive
triangle count and unit normals within 1e-4, rather than incidental emission order.

All 19 focused wrapping/stitching/loop-interior tests pass locally. Midpoint .225
openings at 64 faces and the straight profiles now generate finite output because
of the reviewed angle fix. Genuine failure uses a legacy negative wrapping offset
that removes the surface: status 3 and original diagnostic persist, and the last
mesh remains stale. Successful isolated empty output remains status 5 and clears
the preview. Invalid archives remain status 1.

No native view changes or human interaction are required in this stage. Native
controls, GPU/keyboard/VoiceOver acceptance and Qt differential tolerance remain
pending. Core issue #14 records zero-area triangles, so this is controller and
numerical acceptance, not complete geometry/topology parity.

Full local `make ci` passed on 2026-10-17: 446 tests, formatting, native build,
coverage gates, both Qt-free app linkages and isolated bundle-rebuild regression.
Measured line coverage remains mesh 73/74, document 2812/2896, model 1428/1434,
pure state 529/529, undo 97/97 and orbit camera 33/33. These measurements do not
claim inherited C++ coverage or native interaction acceptance.
