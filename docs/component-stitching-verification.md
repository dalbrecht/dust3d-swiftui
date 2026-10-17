# Component stitching verification

Issue #93 implements closure flags, target segments and loop back-cap depth and
sharpness, with native group controls and the existing lossless undo pipeline.
Inherited reference: component_property_widget.cc uses segments 0–100, depth
0–2 and sharpness 0–1; document defaults are false/zero/one/zero.

## Automated evidence

Four document tests first failed without the settings/command API, then passed.
They cover defaults, known/unsupported/empty values, comma decimals, all fields,
Float underflow rejection, scalar boundaries, segment bounds, missing owners,
exact history, no-op source spellings/redo, node/part/hierarchy preservation,
opaque XML/comments and asset survival through save/reparse. Empty numeric
source attributes remain unavailable rather than being treated as absent.

Six core/controller tests include independently serialized curved line profiles
and concentric closed loops. Closure flags, segment counts, cap depth and
sharpness change finite geometry with unit normals. Supported numeric endpoints
are finite. Scalar controller drafts accept comma decimals, reject invalid text,
and preserve exact undo/redo. Controller history retains component selection,
camera and opaque assets, with no-op redo preserved. A side-closed straight-rail
fixture creates zero-area profiles and is retained as a typed generation failure
with the original core diagnostic; the positive fixture is nondegenerate.

The UI test first failed without ComponentStitchingControls. Eight rendering
tests now share a hidden AppKit window renderer. The new test covers actual
250-point component inspectors and isolated stitching sections, with known and
unsupported source metadata in light/dark modes. Rendering creates no archive
edit or undo entry. Transient PNGs under
/private/tmp/dust3d-component-stitching-ui-qa were inspected for readable labels,
source placeholders, numeric drafts and unclipped controls. No baseline committed.

Full `make ci` passed on 2026-10-17: 416 tests, zero failures, formatting,
native builds, coverage, Qt-free linkage and isolated bundle-rebuild checks.
Measured lines: document 2649/2733, editor model 1417/1423, pure editor state
524/524, undo 97/97 and mesh 66/67. These do not measure native UI/Metal coverage. No dependencies, core revision, CI configuration or app
identity changes. The QA script now selects both part and component render suites.

## Remaining acceptance

Native pointer/keyboard, draft/menu transitions, Save/Undo/Redo menus, VoiceOver
and GPU rendering remain pending while desktop input is unavailable. Reuse
org.dust3d.editor.combine-qa. Finite normals and changed positions do not prove
closed-surface manifoldness or agreed Qt differential tolerances. Fill-loop,
hollow/wrap modifiers, broader M3 and M4–M8 remain incomplete. Full parity is not
claimed.
