# ADR 0105: Query stored animation presentation independently of graph snapshots

Status: Local actor/presentation foundation; native list/inspector UI and evaluation pending (#145).

Keep animation metadata as an optional explicit EditorSession query. Do not add
another XML parse to every graph snapshot or make a catalog interpretation error
break Open, graph edits or Undo. animationSnapshot returns the graph/document/
history snapshot and list from one serial actor observation, preserving the
original optional metadata cause separately from a successfully empty list.

AnimationListPresentation is a pure transform without UI/framework imports.
Rows retain their original DocumentAnimation, use cached UTF-8 bytes as Identifiable
IDs, and derive labels for missing/empty names/types. Unknown types remain raw
stored intent, not runtime capabilities. Swift canonical String identity must
not merge distinct source IDs. UI consumers must correlate document identity/
revision and their request epoch before adopting asynchronous list results.

Selection is actor-owned, transient and independent of graph/bone selection.
It never dirties the document or changes its revision/history. Explicit selection
rejects missing or uninterpretable identities without replacing prior selection;
clearing stays available after optional metadata failure. A query normalizes a
missing/deleted selection to nil, and Redo does not resurrect it. Successful Open
replaces source identity and clears selection; failed Open keeps its old accepted
source, which future scene callers must not relabel as a new document.

Create and duplicate obtain fresh UUIDs in the actor, apply the existing atomic
document command, and select the committed row. Optional presentation failures
retain their cause rather than reversing or misreporting a primary accepted edit.
Checks before work and before state/selection publication honor cooperative task
cancellation; no post-commit cancellation check reports an accepted edit as failed.
These metadata operations never call native rig/animation/audio evaluation.

Tests use only small XML/archive values. They cover fresh UUIDs, exact history,
current revision tags, canonical-Unicode IDs, label fallbacks, graph/animation
selection independence, stale-selection normalization, failed duplicates, edits/
deletion, unloaded/canceled requests and original optional-error isolation across
Open/edit/Undo. The full local `make ci` passes 45 build-support tests and 984 XCTest cases
(119.368 seconds), including six animation-session tests, formatting, coverage
gates, Qt-free linkage and isolated bundle rebuild/signature checks. The pure
presentation file measures 37/37 executable lines. This is not native
UI/evaluation or whole-core coverage. A test closure-array compiler diagnostic
was mitigated by an explicitly typed local array without removing test cases.
Store/list/inspector controls, native catalog/Qt interoperability, playback/audio,
responsiveness and full M6 acceptance remain open. Pin and quarantines unchanged;
no screenshot applies to this actor/data-only stage.
