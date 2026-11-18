# ADR 0126: Additive radius input

Status: accepted; local native release gates passed on 2026-11-01.

## Context

Qt supports equal additive radius changes over selected nodes and selected-edge endpoints. Native absolute fields and multiplicative group scaling do not provide that behavior for heterogeneous radii. Qt derives one step from canvas scene height, not the fit projection scale.

## Decision

Add pure model/session operations accepting finite document-space radius deltas. Resolve the deduplicated effective node group, preserve explicit selection and positions, respect radius locks and read-only/disabled ownership, and clamp explicitly edited radii to 0.001...1. Preserve imported radii until an actual edit. A finite zero delta is a semantic no-op. Rejected or stale inputs leave archive, selection and history unchanged.

Capture document identity/revision, selection and constraint epochs for dispatched canvas adjustments. Hover targets never select a node and are available when there are no selected canvas nodes or edges. A sidebar part or component selection remains active while the hovered node is edited. Positional wheel scaling uses the existing locked centroid operation with factor 1 + sign/H and unchanged radii.

Expose discoverable menu/inspector commands and bare minus/equal shortcuts without intercepting text editing or animation focus. Store actual canvas height per window. A narrow local AppKit boundary routes wheel input over node hits and empty canvas exactly once. Ordinary wheel adjusts selected radii, or a hovered node when the canvas graph selection is empty. Command-wheel scales selected positions on macOS, matching Qt's platform mapping of ControlModifier. Physical Control alone follows ordinary radius behavior. Zero vertical movement and momentum-only events pass through as an explicit native safeguard.

Invalidate hover on exit, plane/document replacement, hidden/deleted targets, and stale contexts. Do not use an app-wide event monitor. Native UI control must wait for the locked Mac to be unlocked; hosted tests can continue.

## Verification and remaining scope

Test heterogeneous radii/equal deltas, overlapping endpoint deduplication, all locks, read-only/disabled ownership, clamp limits and imported values, finite validation, stale targets, one-step undo/redo and no-op identity. Cover actual height changes, both planes, text/animation focus exclusions, wheel target precedence and modifiers, node/empty-canvas delivery, multiple windows and fresh pinned-core preview. Run full native gates before a release checkpoint.

Qt Add mode adjusts a transient ghost cursor radius used at the next placement. Native has no corresponding cursor-placement mode yet. That foundation and its keyboard/wheel behavior remain explicit open parity work; these commands must not turn ghost-radius changes into immediate document edits or be reported as complete input parity. Physical keyboard, trackpad phases, hover and VoiceOver acceptance require native interaction evidence.

Qt reference: document_window.cc:2495–2497; skeleton_graphics_widget.cc:1264–1370,1794–1799,2032–2067,2734–2748; document.cc:1389–1443; document_node.cc:9–16.

Local verification: 243 isolated model tests and 75 combined focused tests passed. Full native gates passed (60 support, 1,214 XCTest, configured coverage including740/740 editor-state lines, Qt-free linkage and isolated bundle rebuild/signatures). Hosted lifecycle tests cover actual height capture, resize replacement, focus loss, disablement/removal and no state callbacks during representable updates. Native physical input and Add-mode ghost placement remain open; no product app was launched by these gates.
