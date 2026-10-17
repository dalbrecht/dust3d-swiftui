# Swift UV metadata verification

Apple issue #121; ADR 0060. Exact reviewed core pin:
9577f8a44966841cf1c946adc726b12ef17e24c5 (core PR #34).

## Failing-first evidence

The initial pure metadata and loader tests fail because the Swift types/API do
not exist. A later regression reproduces Swift-equivalent but byte-distinct image
IDs comparing equal in chart/metadata values (two assertions fail). Explicit
UTF-8 identity comparisons now preserve their distinction. A copy-boundary test
first fails on the absent component-identifier error adapter; the adapter now
preserves the typed original identity cause in MeshLoadingError.

## Current tests

23 targeted tests pass: 13 pure-model, six real loader and four copy-boundary
cases. They cover all corner/chart/color axes, normalized range/finite values,
missing mappings, invalid markers, typed unknown/ambiguous/future associations,
byte-exact original/image identity equality, chart bounds/rotation, gradient
indices/colors/resolution and count/size overflow before unsafe views.

Actual Capsule, Sword and RoundedCrossing loads preserve triangle alignment,
unknown mappings and real seam descriptors. Copied metadata and geometry survive
subsequent loads; concurrent tasks exchange immutable Sendable results. Resolved
image dimensions and alpha-first source color reach charts; unresolved images
and unsupported colors retain native status/cause. Malformed descriptors, aliases,
quota/input failures and cancellation after native generation do not publish
partial values. No image pixels are decoded or baked in these tests.

## Full gate and coverage

Full `make ci` passes: 556 tests, two existing GPU skips, zero failures
(86.399 seconds). Formatting/shell lint, build, coverage thresholds, native source
and both app Qt-link checks, and isolated bundle-rebuild regression all pass.

Measured new-file line coverage: MeshUvMetadata.swift 148/148 (100%);
MeshUvCopy.swift 118/121 (97.52%); MeshUvLoader.swift 109/110 (99.09%). Overall
Swift mesh library: 910/921 (98.81%). Residual adapter lines handle impossible
current-owner buffer inconsistencies, typed conversion of corrupt native metadata
and a missing geometry view; no forged native owners/fault switches are added to
force those defensive paths. This does not establish full inherited engine or
GPU coverage. The two skipped GPU checks remain explicit acceptance limits.
Targeted tests use Swift 6 with warnings-as-errors and real pinned core sources.
No UI changes or app launches are part of this SDK-only stage.

## Remaining limits

RoundedCrossing still reports 128 unknown mappings out of 434 triangles. Separate
scratch core diagnostics identify 126 null/root broken-triangle records; two
remaining faces do not match any original chart triangle even ignoring winding.
No default material or UV interpolation is invented here. Future acceptance must
resolve/reference-test these semantics or report unsupported mappings explicitly.

Known UVs and component association do not prove unique material ownership.
Existing indexed sharing omits UV/material attributes; this result must not be
rendered as a textured indexed mesh without incorporating seam attributes.
Atlas density/packing scale is not an allocated image dimension. Colors remain
in source encoding without color-space conversion. Native quotas exclude Swift
copies and do not bound total memory or runtime. Cooperative cancellation cannot
interrupt inherited native generation. UI/Qt differential, baking/rendered
texture, PBR/transparency, imports/exports and full M3/M4 acceptance remain open.
