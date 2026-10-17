# Indexed Metal verification

Tracking: Apple issue #106; ADR 0053. Depends on merged Apple PR #105 and its exact
reviewed core pin. No new dependency or CI configuration change.

## Contracts

The viewer file service and editor preview service now produce copied indexed
meshes. The shared viewport uploads UInt32 indices and unique position/normal/color
vertices. Expanded public loader and viewport APIs remain available. Camera reset
and mesh revision logic, stale preview failures, successful emptiness and document
history/save paths keep their existing semantics.

## Verification

Failing-first tests rejected the absent indexed file-service and pure rendering
APIs. Pure preparation tests cover normalized bounds, preserved indices/attributes,
expanded triangle order, small bounds, invalid buffers and unrepresentable bounds. A further failing-first device-limit regression
covers exact/insufficient vertex and index limits before allocation, accounting
for the GPU layout stride rather than assuming the native payload budget applies.

An offscreen test constructs real native single-node geometry, runs both expanded and
indexed production Metal passes, copies pixels back after GPU completion, and
compares them exactly on the same device for solid and wireframe drawing. It also
requires visible coverage and fewer covered pixels for wireframe. It passes on the
local Metal device; hosts without Metal explicitly skip it. This is not a committed
cross-machine pixel baseline. Optional PNG evidence uses
`DUST3D_METAL_QA_OUTPUT_DIR` without opening a window or interacting with the desktop.

The first full gate exposed an expanded-array assumption in the smoothing test.
It now reconstructs triangle positions through indices, proves geometry unchanged,
and requires increased vertex sharing after smoothing. The focused regression passes.

Existing editor tests exercise real modifiers/stitching/wrapping, exact history,
successful-empty clearing and stale output on genuine failures with indexed
preview values. Full `make ci` passes: 465 tests, formatting, builds, coverage, Qt-link checks
and isolated bundle rebuild. Mesh library coverage is 140/142 lines; document
2812/2896, model 1462/1468, pure editor state 529/529, undo 97/97 and orbit 33/33.
The local solid and wireframe PNGs were visually inspected; no app was launched. Native pointer/keyboard/VoiceOver acceptance and large-model memory profiling
remain pending. Source IDs, UVs and materials are not implemented by this stage.
