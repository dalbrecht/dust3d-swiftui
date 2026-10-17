# Aspect-aware camera verification

Issue: #73. Decision: [ADR 0037](adr/0037-aspect-aware-camera-fit.md).

## Regression and automated gate

Before the fix, projection tests failed for portrait viewports and the pinned-core
32-triangle disjoint-part fixture. An intermediate distance-only fix exposed
far-plane clipping at aspect 0.01. Automated review then identified float-depth
precision collapse with a fixed near plane; the new regression failed with five
assertions before moving both depth planes with the fitted distance.
Six camera tests now cover sampled unit-sphere bounds across aspect ratios
0.01–8, nonfinite/unavailable aspect, zoom and orbit limits, preservation of
relative zoom and orbit on resize, and actual generated mesh vertices.

`make ci` passed on 2026-10-16: 339 tests, zero failures; native builds,
formatting, Qt-free linkage and both signed app bundle rebuild regressions passed.
Measured line coverage: mesh library 66/67; document 2232/2316; editor model
1394/1400; pure editor state 523/523; undo domain 97/97; pure camera 33/33.
The camera coverage gate is 100%; Metal/native input and inherited C++ coverage
are not inferred from these results.

## Native rendering

Built and strictly signature-verified the initial aspect-fit QA app at the same
path and bundle identity, before the subsequent reviewed near-plane correction.
Opened the preserved two-part document with nodes at X 0.5 and 3, radius 0.1.
Both uncolored generated parts are visible in the portrait mesh preview on open,
after toolbar Fit, and during pointer orbit. Previously this preview was blank
while reporting 32 triangles. The low-resolution single-node core output is
block-shaped; this change does not alter geometry.

Reopened the colored three-node Capsule fixture: its blue lit mesh remains
visible and reports 80 triangles. No document edits or saves were needed for
these presentation-only checks. Native resize/zoom combinations and broader
accessibility/device coverage remain manual acceptance work; projection tests
cover aspect and relative zoom independently of a display server.

The near-plane correction is verified by float-depth regression tests. The QA
app acquired unsaved interactive edits during review, so its process and document
were preserved instead of rebuilding over the running app. Native rendered
evidence above applies to the initial aspect-fit build; the final depth adjustment
has not been separately inspected on GPU.
