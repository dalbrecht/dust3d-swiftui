# 0051 — Native group wrapping controls

Status: Accepted for inspector implementation; native interaction acceptance pending.

## Context

ADR 0049 and ADR 0050 established lossless commands and actor-backed controller
edits. The native inspector needs mode-dependent controls without rewriting
unknown metadata or mixing presentation policy with SwiftUI rendering.

## Decision

Add pure `ComponentWrappingPresentation` and field values in EditorModel, with no
UI framework imports. Only unlinked groups expose controls. None and unsupported
modes retain a mode menu without parameter fields; Skin exposes offset/smoothness;
Cloth exposes all seven geometry scalars. Keep-children and face-count controls
accompany active modes. View-local text drafts reset on document/component/mode
identity and source changes, commit on Apply/Return and discard on Reset Draft.
Unknown modes/flags use disabled placeholder menu items; unknown numeric values
use empty replacement drafts with a visible explanation. No fallback is written.

Keep controls in a focused SwiftUI subview inside the existing scrollable
component inspector. Use native menus/toggles/text fields, semantic colors,
visible ranges, accessible labels/identifiers and text-editing command focus.
Use a vertical mode label/menu so unsupported source text fits at 250 points.

Adopt reviewed core `2776de6933ae5f511e632afee6ffbd0c33dc0b75` (core PR #16).
Positive exported area and precision-failure SDK regressions fail on the previous
pin, then pass with the new pin. The sole float export policy remains in core.

## Consequences and limits

Presentation and hidden-window render tests cover light/dark, None/Skin/Cloth,
unknown modes/parameters, actual inspector composition and no-edit rendering.
There is no supplied reference design; inspect artifacts without inventing a
pixel baseline. Native pointer/keyboard/VoiceOver/GPU acceptance remains pending. Offscreen rendering is not native interaction.
Binding, materials and broad Qt differential acceptance remain later work; these
controls expose the implemented geometry family without claiming full M3 parity.
