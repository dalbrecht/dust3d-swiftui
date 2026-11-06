# ADR 0159: Assignment progress, matching selection and transient highlights

Status: Accepted, issue #363. Physical pointer/keyboard/VoiceOver acceptance remains pending.

Qt BoneManageWidget counts non-CutFace edges for assignment progress, including
read-only and unresolved owners. Progress hover/click matches unassigned edges in
that population; graph selection independently checks visibility/editability.
Bone-row hover matches exact stored names, and Select Bone Edges clears selection
before adding eligible matches, including when none remain.

BoneEdgeOverview prepares progress counts, exact named raw groups, unassigned raw
matches and selectable IDs once from immutable metadata. A resolved CutFace owner
is excluded only from progress/unassigned scope; named scope includes those edges.
Unknown owners count toward progress but cannot pass native exact owner/endpoint
selection eligibility. Empty names are unavailable through the named route.
A nonempty named target with zero eligible matches remains an explicit clear-selection
action. All-assigned/empty unassigned intent is unavailable.

BoneEdgeSelectionTarget freezes raw and selectable IDs and document/window/selection/
constraint epochs. Actor selection replaces transient graph sets without archive,
Undo/Redo or preview changes; cancellation/stale intent rejects before publication.
Controller factories validate initial and dispatch context and clear highlights
before selection. No generator, bake or material preparation is requested.

Transient highlights belong to an inspector surface UUID, exact row identity and
captured target. Exit/disappearance clears only that owner and source target.
Snapshot changes and stop release stale presentation; derived canvas state checks
availability/current context and working/stopped status. Another row, window or
newer source's highlight cannot be cleared by an old exit. Existing visible-node
canvas projection applies visibility. An accent halo and dashed unselected line
distinguish highlights from actual solid edge selection.

The template browser shares the overview for counts, row hover and chosen-bone
selection. Native ProgressView and an explicit accessible Select Unassigned Edges
button replace Qt's thin clickable bar. Stored and selectable counts are separate
and visible. Hierarchy disclosure/selection and global clear/assignment retain
existing semantics.

TDD covers exact Unicode names, CutFace exclusions, read-only/unresolved owner
counts, unsupported endpoints, zero matches, repeat no-op, history/redo/window/
preview isolation, cancellation, selection/constraint ABA, edit/Undo, replacement,
stop and hover owner/late-exit behavior. Controller native services are blocked.
Full CI and exact archive/About validation are required before checkpointing.
Offscreen state evidence does not establish physical UI/HIG acceptance. Generated
skeleton, weights/deformation and full M5 parity remain open. Production core pin,
dependencies and quarantines remain unchanged.
