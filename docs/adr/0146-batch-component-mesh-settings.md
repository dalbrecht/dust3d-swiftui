# ADR 0146: Batch component combine mode and normal smoothing

Status: Implemented locally; native proposal and final gate pending.

## Context

Qt component_property_widget.cc:46–73 applies Combine Mode to every selected
component and emits one groupOperationAdded. Its Normal Smooth control does the
same at 407–410. Native previously exposed these fields only in ComponentInspector,
which NodeInspector renders for one selected component. Existing multi-row role
and wrapping controls do not replace these mesh settings.

Qt setters document.cc:3055–3067 and 3375–3387 impose no role/link/graph-lock guard.
The smoothing widget alone suppresses its UI when preparePartIds 1157–1170 resolves
one unique directly linked CutFace part (condition 401), including multiple references
to that part. Native singleton smoothing already admits every component role/link;
new batch controls retain that native policy. This is a narrow documented widget
admission difference, not an invented group-only or graph-lock restriction.

## Decision

ComponentMeshEdit replaces either combineMode or smoothCutoffDegrees. One
editComponentMeshSettings(ids:edit:) command validates every exact UTF-8 request
before deduplication, reads/indexes one shared hierarchy/DOM and mutates only
explicit rows. Parent selection does not expand to descendants. Empty arrays are
no-ops even with an unused invalid cutoff. Nonempty invalid cutoff/IDs reject before
mutation. The shared public batch bound derives the existing hierarchy limit.

Singleton and batch commands share element-level mutation helpers. Effective
Normal defaults and recognized legacy inverse spellings retain their existing
meaning. A semantic no-op preserves exact source bytes, including legacy inverse;
an actual mode replacement writes the explicit mode and removes legacy inverse.
Unknown source mode remains opaque until explicit replacement. Smoothing uses
finite 0...180 values; absent/empty/negative-zero are effective zero. Equal numeric
spellings remain intact, and an actual zero replacement removes the attribute.
Retain hierarchy, roles, links, flags, unknown fields and every asset. Actual edits
advance geometry and material identities together, matching singleton behavior.
All-noop batches preserve archive, preview identity, Undo and redo.

ComponentMeshSelectionTarget captures raw selected IDs with exact byte indexing
and document/revision/selection/constraint ABA protection. Actor edits stage a copy
and check cancellation before publication. Store factories capture admission and
reject stale, busy/stopped or initially unavailable intentions. UI does not acquire
a later selection or depend on graph visibility/locks.

Multi-selection-only controls display uniform, mixed or unsupported effective
values without implicit edits. Combine choices are explicit actions. Smoothing
uses a String draft, finite validation and disabled invalid Apply; Return uses the
same validated action. Reset Draft is separate from explicit Set Sharp (0°).
Both controls have accessible current values/labels and text-focus isolation; no
new shortcuts. The singleton inspector remains separate.

## Verification and limits

TDD retains missing document/model/Store API RED logs and the empty-invalid-cutoff
contract RED. Pure tests cover legacy defaults, raw Unicode IDs, repeated exact
requests, unsupported and mixed fields, genuine role-bearing locked/hidden/disabled
parts, opaque assets, non-expanded children, no-op spelling/redo and exact Undo.
Model/Store tests cover selection/constraint/document ABA, cross-window isolation,
cancellation, unavailable/busy/stopped callbacks, and invalid drafts. Store tests
stub preview, both baking paths, imported selection and animation catalog before
opening any pure fixture. 320pt light/dark renders cover mixed, unsupported and
uniform controls; no physical desktop keyboard/VoiceOver claim is made.

A first GREEN compile failed in codesign while the disk had 380 MiB free; that log is
retained as an environment failure. Root removed only old generated object/module
caches, and the authorized single retry passed 12 focused tests before final scope
expansion. At that focused checkpoint no native fixtures had been created or executed.
A separately reviewed/hash-admitted native proposal must prove both selected
regions' geometry/normal behavior against independently computed oracles before
claiming native acceptance. Core 48b and Package.resolved remain unchanged.

Final pre-native focused scope passes 23 tests (new pure/model/stubbed Store plus
existing singleton combination/smoothing contracts). New pure files and shared
field helpers have 100% lines, regions and functions in that focused profile:
ComponentMeshBatch31/31 lines, ComponentMeshSelection58/58, Combination33/33 and
Smoothing37/37. LLVM Swift coverage reports no branch records; region coverage is
reported instead, without claiming unavailable branch instrumentation.

At 320pt, full current combine status wraps in a separate caption, while a concise
native menu retains count-aware accessible current state. Mixed, unsupported and
uniform controls render in both appearances. SwiftUI view closure coverage is
87.35% of lines and 86.49% of regions: native menu item invocation, Return submission,
Reset Draft activation and the inline invalid-draft caption remain UI-boundary
acceptance residuals. Their underlying parsing/captured Store actions are tested;
no physical interaction or 95% view coverage is claimed. No app-wide input monitor
or test-only production hooks are introduced for coverage.

After independent source/hash admission, the single approved native acceptance
method passed once on production core 48b. Three ordinary disjoint default single-
node parts produced 48→16→48 triangles through real Store batch combine actions,
matching an independently authored anchor. A Swift geometry-only angle×area oracle
verified 180° normals for both selected regions (40 changed corners each) while
the fixed region stayed flat. Duplicate coincident faces and disconnected incident
fans are rejected; no generic seam/position-welding equivalence is claimed.
The actual graph, camera and selection stayed unchanged, and one-step Undo restored
flat normals and exact archive; redo and reopen retained the independently expected
normals. All five admitted inputs, production source, pin/core and linked test-host
hashes were unchanged before/after. The pure 23 and native 1 test hosts are retained
read-only with their separate tested identities; later documentation updates do
not imply those hosts were built from a later source digest. Preview geometry and
normals only: baking/import/catalog services were blocked, and no material, GPU,
imported-seam, physical keyboard or VoiceOver acceptance is claimed.
