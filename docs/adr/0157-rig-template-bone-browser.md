# ADR 0157: Browse pinned template bones before assignment

Status: Accepted for implementation, issue #359. Physical interaction acceptance remains pending.

Qt BoneManageWidget loads the template XML into an ordered parent hierarchy,
shows counts for all stored edge names and assigns the selected template name to
explicitly selected edges. Native batch assignment already supplies an atomic,
captured-target command. Requiring users to type names leaves this workflow incomplete.

Read only the existing hash-verified pinned resources through RigTemplateResources.
RigTemplateHierarchy exposes source-order flat bones and ordered roots. Exact UTF-8
identity preserves distinct spellings. Forward parents resolve before construction;
unresolved parents become roots as in Qt. Invalid types, empty/duplicate names,
cycles, oversized data and entity declarations reject the whole hierarchy.
Original resource errors remain distinct. This parser does not invoke core generation.

RigTemplateBrowserContext freezes membership, all-edge stored counts and assignment
and window epochs once per render. SwiftUI OutlineGroup provides disclosure controls;
choosing a row is local browser state. The separate Assign button uses the existing
captured batch action, so stale selection/Undo/replacement/window intent cannot
retarget. Unknown stored names remain editable in the existing exact-name field.
Resource loading runs off the main actor and cancellation prevents stale publication.

Tests cover all seven pinned templates, exact Unicode/order, forward and unresolved
parents, invalid metadata, counts, template mismatch and stale/other-window contexts,
plus existing atomic assignment contracts. Full CI and independent archive validation
are required before release. Physical keyboard/VoiceOver/disclosure/focus acceptance
remains pending. This is template browsing, not generated skeleton display, weights,
deformation, pose evaluation or completion of M5. Core pin/quarantines remain unchanged.
