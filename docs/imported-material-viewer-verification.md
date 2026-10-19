# Imported material viewer verification

Tracked by #157; implementation decision ADR 0074. This document records local
acceptance; hosted review/CI and native evidence must be recorded before merge.

## Implemented scope

The standalone viewer prepares supported embedded GLB source/material/image facts
from one immutable archive snapshot, renders authored UVs with per-model samplers,
and applies source/factor color, scalar PBR and alpha/sidedness policy. The editor
and system file-preview services retain their existing representation. Imported
atlas/baking, additional GLB features/maps, textured exports and full M4 acceptance
remain open. Original assets are preserved rather than regenerated.

## Tests already observed

- Five preparation tests pass for source/material/image alignment, byte-exact joins,
  original codec/native causes, factor-only models, procedural fallback and exact/
  aggregate decoded limits.
- Numerical geometry, image, sampler and order tests pass for source UVs outside
  0–1, per-corner color/alpha, inverse sRGB before interpolation, material factors,
  all explicit filters/wrap axes, actual buffer limits, exact payload and bounded
  binding/draw admission. Invalid metadata uses explicitly tiny backing buffers.
- Ten actual imported Metal tests pass locally, including a real owned GLB source,
  requested mips, asymmetric texture orientation, negative/repeated coordinates,
  linear-space filtering, minified checkerboard versus an independent linear
  factor reference, PBR scalars, OPAQUE/MASK/BLEND, sidedness and wireframe.
- Existing baked-renderer hardware tests pass after extracting the shared display
  calculation. Imported PNG 2/4/8-bit keyed grayscale preserves hidden RGB, while
  the legacy bake decoder's Qt-compatible outputs remain unchanged. JPEG failures
  retain specific localized causes.
- Viewer/viewport tests pass for preserving orbit/zoom, rejecting old loads/GPU
  callbacks, geometry fallback, exact-snapshot retry and GPU-frame acknowledgment
  before removing the recognized imported limitation.

Full `make ci` passed locally: 31 build-support tests, 767 XCTest cases, formatting,
coverage gates, Qt-free linkage and isolated app/provider rebuild checks. The final
run used temporary compiler-cache paths and process inspection access; earlier
sandbox failures were compiler-cache/`ps` restrictions, not passing gate results.
Measured library lines: Kit 2073/2100, document 3471/3559, editor model 1545/1551;
pure editor state 534/534, undo domain 97/97 and orbit camera 33/33. New preparation/
value files cover 77/78 lines; geometry/order/sampler 305/311; Metal resource builder
167/174; imported renderer lifecycle 111/166. Native presentation/error callbacks
and allocation failures are not fully exercised by coverage; these GPU boundaries
are explicitly outside the pure-library coverage claim. Metal tests explicitly skip when no device is available;
reported local hardware results above did not skip. No whole-engine/GPU coverage
or Qt pixel-parity claim is made.

## Interface review (full mode, scope: viewer material adoption)

Framework/styling: existing SwiftUI/AppKit desktop controls, semantic system colors,
SF Symbols and caption/status typography. No new design system or custom animation.

| Category | Evidence inspected | Current result |
| --- | --- | --- |
| Typography | Viewer status/count/error source and lifecycle tests | Tabular counts inspected in the running dark-appearance viewer |
| Surfaces | Existing window/progress/retry layout | Native empty, loaded, wireframe and recoverable error states inspected |
| Icons | Existing SF Symbols and material-notice state | Existing system icons inspected in toolbar and failure notice |
| Animations | Source and revision/cancellation behavior | No new custom motion; browser 10% replay is inapplicable to native system progress |
| Performance | Actor upload/preparation, pure quota/order tests and GPU encoder | Heavy material work off-main; large-scene timing and driver/RSS limits remain M8 work |

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM | Viewer material notice | Imported warning remained even for supported source facts | Remove only its recognized notice after a current successful GPU frame; restore on failure | Accurate state feedback prevents misleading completion |
| MEDIUM | Viewer progress | CPU preparation completion hid progress before GPU presentation | Keep progress through current-frame acknowledgment; stale callbacks cannot clear it | Loading reflects the displayed result |
| LOW | Viewer count status | Proportional changing digits | Native monospacedDigit status counts | Tabular numbers reduce layout shifts |

Considered but rejected: a custom material-panel style would introduce competing
chrome; orbit/texture entrance animation would repeat on frequent operations;
removing all engine warnings would hide procedural/unknown limits. Verdict: **Approve for this viewer stage**, subject to exact-head automated review
and all hosted checks before merge. This does not approve full M4 or production parity.

## Native acceptance

Staged with `DUST3D_APP_OUTPUT_DIR=/private/tmp/dust3d-viewer-screenshot
./script/build_and_run.sh --build-only`; launched and controlled through native
computer-use tools with the existing `org.dust3d.viewer` identity. Inspected empty
state, opened the unchanged `ImportedSurface.ds3` (1 part, 2 nodes, 4 triangles),
observed masked material presentation and removal of its recognized warning,
orbit/zoom, Fit Model and wireframe. Screenshots were inspected inline; no local
pixel baseline was invented.

A disposable `/private/tmp/ImportedMaterialFailureQA.ds3` retained the fixture's
archive/model geometry but replaced its 80 embedded PNG bytes with zeros. Opening
it retained geometry and reported “The image is not a complete, supported PNG.”
with the original compatibility warning and enabled Retry Materials. Retrying
retained the same diagnostic and usable geometry. No source/user document was edited.
The viewer was quit before the final committed-identity rebuild.

The first native panel temporarily disabled Open for both existing/new fixtures.
An unsandboxed type diagnostic confirmed the registered `org.dust3d.document`
conformance/readability; reopening the panel then opened both selected paths.
No type-registration fix or fresh-install distribution acceptance is claimed.
Native progress/stale-frame timing is primarily covered by deterministic store/
viewport tests; broad VoiceOver, light appearance and production timing remain
part of wider acceptance. Hosted Metal tests may skip when no device exists.
