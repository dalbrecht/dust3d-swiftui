# ADR 0132: Precision canvas nudge and selected-node spacing

Status: accepted for local delivery; physical keyboard and VoiceOver acceptance outstanding.

## Context

Qt exposes bare arrow keys and brackets in document_window.cc:2499–2505. In skeleton_graphics_widget.cc:2091–2156, arrows move the checked origin or merged explicit-node and selected-edge endpoint positions by one scene unit divided by canvas height. Brackets call scaleSelected(-10/+10) at 2159–2175; its two-profile construction at 1293–1335 gives uniform three-dimensional position scaling by 1±10/H about the merged-selection centroid, retaining radii. H is logical canvas height, independent of fitted projection scale.

## Decision

Provide captured actor commands and accessible Nudge and Spacing controls, native menus and node/canvas context menus. Bare arrows and brackets are handled only by the actual canvas/node/origin first responder. Sidebar navigation, native text editing, animation controls and mesh-preview responders retain their input. No global bare key equivalent is installed. Add mode declines these inputs. While Move Origin is checked, arrows move only the supported stored origin; brackets still space the selected graph and preserve the tool.

Capture document, revision, selection, constraint, plane, logical height and tool/layout generations at admission. A retained callback from an obsolete context cannot become current again after an away/back transition. Once a key is accepted, later layout or tool changes do not reinterpret or retroactively discard its captured delta; actor document/selection/constraint checks and cancellation still apply. Preserving origin mode skips automatic exit without re-enabling a tool explicitly turned off later.

Respect established native readonly and axis locks, unlike Qt's lock bypasses in some transform paths. General spacing accepts finite signed factors, including collapse at H=10 and reflection below it; bounded output validation remains atomic. Existing positive-only general scale APIs retain their contract. Tiny-height degenerate cases are verified only by pure model tests, never native geometry generation. No-op commands preserve redo and preview state; effective edits have one undo.

Native pointer activation takes canvas focus only on an actual press. Successful gestures retain it directly. Cancellation restores an attached prior responder only while the gesture still owns focus; explicit focus changes win. SwiftUI update, removal and dismantle clear native admission synchronously and defer the cancelled owner's captured callback/token, avoiding synchronous model publication during view updates or cancellation of a newer gesture.

## Verification

Test-first red receipts precede model and UI implementation. Focused lifecycle validation passed 27 tests, including signed position-only spacing, mixed endpoint deduplication, origin locks and repeated nudges, stale epochs, accepted-height capture, two-dimensional native node/origin focus, text/list/mesh responder isolation, focus loss and token-safe deferred dismantle. Hosted light/dark controls are rendered separately. Full combined regression and configured coverage must pass before acceptance. Physical keyboard delivery and VoiceOver remain manual acceptance work; no physical application control was used.

Final combined pinned make ci completed exit 0: 60 BuildSupport tests and 1,364 XCTest tests, configured coverage including 903/903 EditorState lines, Qt-free linkage and isolated bundle rebuild/signature checks. PrecisionCanvasEditing achieved 55/55 lines, 8/8 functions and 31/31 regions after explicit per-axis spacing lock regressions. These results do not establish complete Qt parity or physical HIG acceptance.
