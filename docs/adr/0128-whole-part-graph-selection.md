# ADR 0128: Whole-part graph selection

Status: accepted; local native release gates passed on 2026-11-01.

## Context

Qt Select Part and canvas double-click replace selection with the target part's explicit nodes and edges. Native Part Inspector currently selects only nodes, which cannot immediately drive whole-part midpoint/reverse commands.

## Decision

Provide typed part, node and edge targets. Resolve ownership from actual node/edge metadata, not inferred endpoint membership; preserve an optional parsed edge part identity. Missing or stale targets reject atomically without clearing current selection. Preserve native hidden/read-only inspection behavior, while mutation availability remains separately validated.

Replace both explicit graph sets in one selection epoch, clear exclusive part/component selection, and leave archive, history and preview identity unchanged. Keep the nodes-only convenience separately named. Component reveal uses a separate transient hint: expand ancestors and scroll to the owning row without selecting that component and discarding graph selection. Repeated selection can request reveal again without fabricating a graph-selection change.

Route the targeted action through part/node/edge inspectors and context menus, and native node/background double-click. Consume the double-click without a later single-click or drag replacing its result. Add-mode left-press placement retains precedence. Do not reproduce Qt's first-part fallback when no valid hovered target exists.

A first click may still be awaiting a pure selection actor operation when its double-click arrives. Retain only the latest captured whole-part intent during that pure-pick flight, then apply it if document identity/revision and interaction context remain current. Do not queue through document mutations or replacements, and do not introduce a generic mutation queue.

## Verification

Test part/node/edge targets, explicit owned edges, disconnected islands, multiple parts, both planes, hidden/read-only inspection, malformed/missing ownership, missing/stale targets, one epoch and stale-drag invalidation. Verify unchanged document/history/preview, component reveal preserving graph sets, repeat reveal, whole-part batch eligibility and actual native count-one/count-two sequences without an artificial wait. Cover pending pure-pick, mutation/new-document rejection and Add-mode precedence. Run full native gates and inspect sidebar/selection renders before a checkpoint. Physical double-click, focus and VoiceOver remain separate acceptance evidence.

Qt reference: skeleton_graphics_widget.cc:391–394,1818–1824,2792–2814,2981–3028; document_window.cc:814.

Local verification:276 isolated model and260 document tests passed;103 combined focused tests passed. Full native gates passed (60 support,1,263 XCTest, configured coverage including880/880 editor-state lines, Qt-free linkage and isolated bundle rebuild/signatures). Hosted tests verify native count-one/count-two sequencing, retained stale actions, pending-pick handling, ancestor expansion and actual owner-row visibility in a constrained sidebar. Physical double-click/focus/VoiceOver remain open; no product app was launched by these gates.
