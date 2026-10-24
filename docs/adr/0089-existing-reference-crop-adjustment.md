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
The Mac initially locked before normal Quit; the subsequent controlled native
checks below supersede that temporary limitation. Never overwrite a running QA
bundle or ask humans to push buttons.
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

Verdict: Approve static preview presentation and the native checks recorded below;
keyboard focus/VoiceOver, held Escape and gesture
replacement ordering still need controlled acceptance. This review does not
replace automated PR review.

## Controlled native acceptance (October 23)

The canonical QA bundle was rebuilt only after normal Quit and process-exit
verification, reusing `org.dust3d.editor.combine-qa` and the shared build root.
The loaded About panel reports clean source
`7d41f60f0738a16dec158056f0b0c21bc49b78d5`, digest
`0f9e381b8917c082dcf881b5aae4ba477830d196c1ea8b7d11896f1e8ddb0270`,
unchanged core `41af7d4c1b67dd037e02858e3ef0fdb96a84aebb`, and process
55725. Subsequent documentation edits do not alter that captured runtime identity.

A bounded synthetic 200×160 grid in an owned QA document verifies physical Draw
selection `(20,20,120,80)` and automatic switch to Adjust. Moving changes only X/Y
to `(40,40)`; dragging the bottom-right handle changes size to `140×100`.
Escape dismisses the draft with Undo/Redo disabled and no applied reference.

Applying a fresh `(20,20,120,80)` crop with profile-center origin enabled adds
`canvas.png` (1536×512) and origin `(0.75,0.5,2.25)` in one transaction. Archive
inspection confirms the remaining model tree and existing assets are unchanged.
Keyboard Undo followed by Save restores the exact original archive bytes; Redo
and Save restore the exact applied archive bytes. Closing/reopening renders the
saved reference and 80-triangle mesh, retains the origin, and starts with disabled
Undo/Redo. Runtime identity, screenshots and the four archive states are retained
in the reboot checkpoint; public evidence is linked from
[issue #56](https://github.com/dalbrecht/dust3d-swiftui/issues/56#issuecomment-6374481432).

The Side panel was separately imported and mirrored (the control changed to
Unmirror Side). Physical Draw, move and bottom-right resize produced displayed
crops `(20,20,120,80)`, `(40,40,120,80)` and `(40,40,140,100)`. Escape discarded
that draft with disabled Undo/Redo; the saved applied archive remained byte-exact.
This UI observation does not independently prove internal source-coordinate
conversion, which remains covered by the pure mirrored-draft contracts.

These checks do not establish held-gesture Escape, VoiceOver, complete keyboard
focus routing, Qt differential behavior or full M2.

## Limits

This is a local implementation stage, not full M2 or Qt parity acceptance. No
source image, archive format, core pin, dependency, license or quarantine changes.
No crash, allocation-failure, signal, broken-pipe or resource-exhaustion probes.
