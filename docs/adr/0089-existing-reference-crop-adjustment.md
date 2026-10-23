# ADR0089: Existing reference crop adjustment

Status: implemented locally for #56; full local gate passed; native interaction, public review
and hosted CI pending.

## Decision

The composer previously drew a new rectangle or accepted numeric fields but could
not move or resize an existing selection. Preserve unrestricted Draw as the default,
add explicit Adjust, and switch to Adjust after drawing. Use eight visible edge/
corner handles; interior drags move the existing rectangle, outside drags draw.
Pure ReferenceCropProjection geometry chooses the operation from the initial
pointer position and immutable displayed crop. Resize preserves opposite edges
and initial grab offset, never inverts, and retains at least one pixel. Move
preserves extent and clamps translation. Normalize and bound finite pointer values
before integer conversion/subtraction. Reject mismatched source dimensions.

Use semantic accent/background styling and bounded handle hit regions, adapting
for small crops so regions do not overlap. Numeric fields remain available for
precise keyboard editing. No per-frame native generation or image composition: only
a transient outline changes until pointer end updates the existing draft service.
The panel preview identity includes displayed crop and tool so source/numeric/tool
changes replace the recognizer and clear activity. Existing draft expected-source
checks reject obsolete completion. Mirror coordinates still map through the draft.
Sheet Apply remains the sole atomic document image/origin transaction.

## Verification

The initial adjustment contracts failed to compile because the missing methods and
handle types did not exist. Five pure contracts cover movement/limits, all eight
handles, one-pixel bounds, initial grab offset, small-crop hit regions, drawing and
invalid coordinates/source. Mirrored draft integration proves displayed movement/
resize maps back to original source pixels. Existing stale-source, active gesture,
Apply, cancellation and composition contracts remain in the focused selection.
Twenty-eight focused contracts pass, including actual SwiftUI preview renders for
Draw/Adjust in light/dark and mirrored/unmirrored states without publishing a crop.
No pixel baseline was committed. Full `make ci` passed 36 build-support tests and
893 XCTest cases (zero failures; no runtime skips reported) in 112.65s, coverage
thresholds, Qt-free checks and isolated bundle/provider packaging. Scoped projection
coverage is 114/114 lines, 61/61 regions and 18/18 functions. Compiler-attributed
composition-view coverage remains 19.70% of lines and 13.68% of regions: offscreen
renders do not establish pointer callback, sheet workflow or native accessibility
coverage. The thin SwiftUI boundary retains explicit manual verification gaps.
The legacy pinned core wrote its known global stitch SVG during ordinary fixtures;
retained original bytes and mtime were restored after validation. The existing
running QA bundle hash was verified unchanged after isolated bundle tests.
Native interaction is unverified: the Mac locked before normal Quit of the previous
QA process. Do not overwrite that running bundle or ask humans to push buttons.
All validation reuses /private/tmp/dust3d-validator-safe-build.

## Interface review (full, bounded scope)

Scope: crop projection/preview and composer panel. Framework: existing SwiftUI,
semantic system colors, caption typography, segmented controls. No new dependency.

| Category | Evidence | Result |
| --- | --- | --- |
| Typography | Caption instructions, pixel dimensions, panel source | Monospaced dynamic dimensions; full native panel pending |
| Surfaces | Light/dark mirrored/unmirrored preview renders | Accent outline and eight legible handles inspected |
| Animations | Gesture/source code | No animation added; geometry feedback remains immediate |
| Icons | Existing panel/preview source | No icons added; handles are decorative, numeric fields remain accessible |
| Performance | Projection tests and gesture source | Constant eight-handle geometry; composition only on completion |

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM | ReferenceCompositionSheet.swift crop panel | Only a fresh rectangle could be drawn | Explicit Draw/Adjust tools and contextual instructions | Avoid ambiguous full-image movement and preserve new selection |
| MEDIUM | ReferenceCropPreview | Outline only, fixed blue | Eight accent/background handles and bounded hit regions | Make resize targets visible within the existing styling system |
| LOW | Crop pixel dimensions | Proportional dynamic numbers | Monospaced digits | Keep changing image dimensions visually stable |

Considered but rejected: separate 40-point hit boxes on every tiny crop handle
(overlap would make targets ambiguous); animated drag outlines (continuous pointer
feedback should remain immediate). Existing numeric fields provide precision
where small preview crops cannot offer large pointer targets.

Verdict: Approve static preview presentation; native complete-sheet interaction,
keyboard/focus/VoiceOver, held Escape and gesture replacement ordering still need
controlled acceptance. This review does not replace automated PR review.

## Limits

This is a local implementation stage, not full M2 or Qt parity acceptance. No
source image, archive format, core pin, dependency, license or quarantine changes.
No crash, allocation-failure, signal, broken-pipe or resource-exhaustion probes.
