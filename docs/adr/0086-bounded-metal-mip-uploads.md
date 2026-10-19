# ADR 0086: Bounded Metal mip uploads

Status: Local implementation under #176; public review pending. Related: #175,
M4 #143 and core #59.

## Decision

Extend the existing source-aware resource builder with explicit owned mip chains
indexed by the five established map slots. The production app inputs remain
base-only until the reviewed native accessor/copy integration supplies chains.
No new renderer, global mip generation, dependency or UI control is introduced.

Upload preflight requires valid selectors, an exact matching base image, available
levels for every present map, and a producer cap no larger than each chain's safe
cap. Optional absent maps retain their constant one-pixel fallbacks. Preflight
charges geometry/index buffers and every uploaded level against one combined GPU
payload quota before Metal allocation. CPU storage, driver allocation overhead
and in-flight resources remain outside that logical quota; it is not an RSS cap.

Create each texture with exactly the retained level count and upload every level
explicitly. Keep color/emission sRGB and normal/scalar maps linear at every level.
Enable linear mip filtering only for positive supported LOD. Convert the producer's
Double maximum to Float by rounding down when nearest rounding would exceed it;
base-only rendering keeps filtering disabled. Never infer missing mip pixels from
base dimensions. Account for alpha in every color level when conservative unknown
policies choose depth/blend routing. Explicit material alpha modes remain intact.

## Evidence and limits

Test-first CPU contracts cover exact/one-byte-short aggregate quotas, base-only
regressions, every PBR map, missing/mismatched/insufficient chains, absent/invalid
slots, formats, minified alpha and Float bounds. Real Metal readback using production
resource construction verifies uploaded level counts, fractional LOD trilinear
blending and requests clamped above the producer cap. A separate actual production
fragment render distinguishes retained mip data from the base during minification.
These use deliberately distinct diagnostic level colors, not a physically generated
atlas or portable pixel baseline. Focused GPU/rendering tests pass (22 cases).
An earlier local checkpoint `make ci` passed 869 XCTest cases and 31 build-support tests,
coverage checks, Qt-link checks and bundle-rebuild checks. At that checkpoint BakedMetalUploadPlan
measured 122/122 lines, 59/65 regions (90.77%) and 13/13 functions. The Metal
resource builder measured 141/144 lines (97.92%), 55/63 regions (87.30%) and
12/12 functions. Residual native allocation failures are not claimed covered;
this is not full engine/editor coverage. That checkpoint GPU run succeeded on
the local Metal device; the tests explicitly skip when no device is available. Current integration results
are recorded in the delivery PR; historical counts are not current measurements.

Current app-produced source data and the exact core dependency pin remain unchanged.
Native level binding and retaining the owned chains in source results are required
before app adoption; procedural/mixed and large-model visual acceptance, chart
packing improvements and textured export/re-import remain open. This stage does
not establish full M4 parity. No interactive app UI changed; GPU proof is offscreen.
