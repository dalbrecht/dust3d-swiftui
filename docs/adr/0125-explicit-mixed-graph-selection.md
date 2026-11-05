# ADR 0125: Explicit mixed graph selection

Status: accepted; local native release gates passed on 2026-11-01.

## Context

Qt allows explicit node and edge selections together. The native editor currently has a node set and a mutually exclusive single edge. Inferring edge selection from selected endpoints cannot represent an arbitrary edge subset and would split or reverse unintended edges.

## Decision

Retain independent explicit node and edge sets. Keep existing replacement-selection APIs, and derive the legacy single-edge accessor only when exactly one edge is selected. Add atomic mixed, additive and toggle selection routes. Component/part selection remains exclusive with graph selection. Selection epochs, stale gesture checks, pruning and per-window state cover both sets.

Resolve participating nodes per command, not through one universal inferred selection. Midpoint and explicit reverse consume captured selected edges in UUID order; newly created segments are not captured. Most transforms operate on the deduplicated union of selected nodes and selected-edge endpoints. Exchange X/Z, copy and reduce consume explicit nodes only. Copy includes induced edges between copied nodes. Mixed Cut copies explicit editable nodes, then deletes both explicit sets in one history step, matching Qt. Invalid/read-only selected edges block Cut before clipboard replacement. Delete normalizes combined explicit edge/node removal once so part splitting and history are atomic. Preserve edge-only Cut disablement rather than silently deleting without a new clipboard copy. The existing inferred reverse-between-selected-nodes command remains separately named.

Provide batch edge commands in menus and inspectors, plus additive/toggle selection in the canvas and accessible edge sidebar. Expose clear selection membership and shared enabled/disabled state. Do not add arbitrary shortcuts or change the production core pin.

## Verification

Test disjoint and adjacent edges, explicit subsets of loops, mixed overlapping endpoints, UUID ordering, duplicate picks across projections, replacement/add/toggle selection, readonly inspection, stale drags, component clearing, command-specific transform/copy/reduce behavior, combined deletion/splitting, quotas, one-step undo/redo and per-window routing. Validate fresh pinned-core preview and light/dark inspector rendering before full native release gates. Physical keyboard, modifier interaction and VoiceOver remain separate acceptance evidence.

Qt reference: skeleton_graphics_widget.cc:535–583,1246–1261,1835–1941,2734–2748,3094–3107; document.cc:2194–2208,3606.

Local verification: 231 isolated model and 260 document tests passed, followed by full native gates (60 support, 1,194 XCTest, configured coverage including 679/679 editor-state lines, Qt-free linkage and isolated bundle rebuild/signatures). Bulk midpoint processing indexes the graph once and validates aggregate quotas before mutation. Eight UI artifacts were inspected. Native clipboard handoff, physical modifier/keyboard input and VoiceOver remain outstanding; the Mac was locked when native inspection was attempted. Nothing was launched by these gates.
