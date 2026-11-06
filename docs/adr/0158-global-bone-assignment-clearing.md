# ADR 0158: Clear stored assignments for a bone or template chain

Status: Accepted, issue #361. Physical UI/VoiceOver acceptance remains pending.

Qt BoneManageWidget::clearBoneAssignments and clearBoneChainAssignments clear
exact-name matches throughout the document, including locked/hidden parts;
Document::setEdgeBoneName changes metadata without geometry editability checks.
Selected-edge Clear All has a distinct scope and retains its existing admission.

Add explicit clearEdgeBoneNames(ids:) as a metadata-only document command. Validate
all exact IDs and resolve all changed XML elements before removing attributes in
one owned DOM. Unknown XML/assets and other names remain unchanged. Empty or
already cleared requests preserve history/redo. Ordinary setEdgeBoneNames remains
restricted to editable owners/endpoints. No lock state or geometry is changed.

BoneAssignmentClearTarget captures exact nonempty names, matching edge IDs and all
source/window/selection/constraint epochs. Initially empty intent remains
unavailable. Actor and controller both reject stale intent; cooperative cancellation
before publication leaves the original state. One command commits one Undo step,
retaining graph selection and geometry/material preview identities.

The browser context resolves a chosen bone and descendants using the verified
pinned hierarchy and freezes matching targets from its source snapshot. Separate
Clear Bone and Clear Bone Chain buttons expose counts and explain that matching
assignments in hidden/locked parts are included. Unknown names and case/Unicode
distinctions are preserved. Browsing and ordinary assignment behavior are unchanged.

TDD covers atomic XML/assets/history, readonly/unsupported owners, exact names,
subtree/sibling exclusion, wrong template/window, initially unavailable/stale/Undo/
replacement/stop/cancelled intent, controller publication and preview isolation.
New controller tests block native services. Full CI and exact package validation
are required before a checkpoint. No new native generation/evaluation, dependency,
core pin or quarantine change. Generated skeleton/weights/deformation and full
M5/Qt/HIG acceptance remain open.
