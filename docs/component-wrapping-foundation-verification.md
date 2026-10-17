# Wrapping foundation verification

Apple issue #98; ADR 0049. Core pin:
`49faaf333255199cdbfaf8b46be445e75d55e55d`.

The initial document tests failed to compile because the typed API did not yet
exist. Before implementation, the prerequisite core numeric rejection test also
failed with "Invalid numeric fixture was accepted"; core PR #12 corrected that
boundary and passed automated review plus all six Linux/macOS CI checks.

Document tests exercise mode-dependent defaults, known and unsupported spellings,
finite Float-representable editing boundaries, explicit replacement, group-only
ownership, source graph/hierarchy/comments/opaque XML/assets, semantic no-op bytes
and redo, and exact undo/redo. Actor-session tests verify failed mixed batches
publish no partial state and retain selection, locks and redo.

The independent synthetic `.ds3` fixture is authored in
`Tests/Dust3DKitTests/ComponentWrappingCompatibilityTests.swift`: one node centered
at (.5,.5,.5), radius .2, a Model part nested in an unlinked group, 64 target faces.
It contains no user data or external assets and is MIT project test source.
Both Skin and Cloth produce nonempty triangles, finite positions and unit normals
within 1e-4. More target faces increase actual triangle count; keeping children
adds their geometry. Offset changes surface bounds by more than .01 model units.
Other configured scalars are checked for finite output, without claiming each
must change this simple sphere. Comparisons use triangle counts/bounds rather
than incidental emission order. No Qt differential tolerance is established.

An integration failure revealed core issue #13: Cloth top/bottom openings .225 at
64 faces produce nonfinite output and status 3 with the original diagnostic.
Explicit negative tests retain that failure contract. At 256 faces these openings
produce finite output; at 64 faces .1 openings also pass. This is a tracked
inherited defect, not accepted wrapping parity. A temporary standalone probe
found Cloth at 1200 faces took about 4.4 seconds locally; future controller tests
must allow realistic completion times without blocking the UI actor.

No native view changes in this stage. Pointer/keyboard/GPU/VoiceOver acceptance
remains pending while the user is unavailable. No manufactured pixel baselines
or inherited full-core coverage claims.

Full local `make ci` passed on 2026-10-17: 443 tests, formatting, native build,
coverage gates, both Qt-free app linkages and isolated bundle-rebuild regression.
Measured line coverage: mesh library 73/74; document library 2812/2896 (all 134
new document lines covered relative to the prior 2678/2762); editor model
1428/1434; pure state 529/529; undo domain 97/97; orbit camera 33/33. These Swift
measurements do not establish inherited C++ engine coverage.

Automated review found that wrapping-only commands initially decoded the node
graph unnecessarily. A regression with a node referencing a missing part failed
with `invalidNode`, then passed after all four wrapping commands joined the
existing component-only path. It verifies unchanged opaque node XML/assets and
exact undo/redo without claiming the opaque graph is editable or renderable.
The full gate passed again after this correction.
