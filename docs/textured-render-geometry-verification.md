# Seam-aware textured geometry verification

Scope: Apple #127 and ADR 0063. Internal pure preparation; existing apps/shaders are unchanged.

## Targeted tests

The first build failed because TexturedRenderGeometry did not exist. Twelve
geometry tests now pass: seven new contracts and five existing ordinary geometry
regressions. The initial actual-engine fixture lacked the required canvas origin;
adding explicit zero origins made that fixture valid without altering the engine.

New tests prove deterministic matching-corner sharing; separated position, normal,
color, UV, tangent direction, handedness, component identity/kind and mapping flags;
source Double UV distinctions that quantize to equal Float shader samples; unknown,
ambiguous and future associations; finite-value/tangent validation; exact logical
budget acceptance and rejection; both vertex-dominated and index-dominated device
limits; cancellation; and triangle/attribute preservation with an actual native
bake. Normalization matches the ordinary rendering path.

## Full gate

`make ci` passes: 587 tests, zero failures (88.961 s), strict formatting,
full native build, required library/domain coverage, Qt-free source/both app
linkages, and isolated bundle rebuild regression. Swift mesh library: 1413/1432
lines; document: 2984/3072; editor model: 1490/1496. Pure state 529/529, undo
97/97 and orbit 33/33.

A targeted llvm-cov export from the completed full-gate profile reports
TexturedRenderGeometry.swift 98/98 lines and RenderGeometry.swift 69/69 lines.
These are line measurements for the pure preparation paths, not inherited-core,
shader, Metal allocation or native UI coverage.

Automated review and every remote CI check remain required before merge.

## Boundaries

The logical quota covers vertex/index payloads only. Source storage, retained
metadata/textures, dictionary workspace and allocation overhead remain additional.
No shader, texture upload, GPU rendering, window/input behavior, PBR, transparent
ordering, AO or export acceptance is established by this stage. The native apps
continue using their existing geometry previews.
