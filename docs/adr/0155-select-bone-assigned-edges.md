# ADR 0155: Select graph edges by stored bone assignment

Status: Implemented; full gate and physical acceptance tracked separately

## Decision

Provide Select Bone Edges in the single-edge inspector. Qt reference
BoneManageWidget::selectBoneEdges clears graph selection and adds edges matching
the selected boneName; its graphics selection path checks visibility/editability.
The native action derives the name from the inspected edge and matches exact
UTF-8 spelling across parts. It needs no generated rig or native evaluation.

Extend GraphInspectorActionContext rather than add another command dispatch path.
Prepare the eligible edge set once per inspector render, retaining supported
editable endpoints and an exact editable assigned edge owner. Legacy part aliases,
hidden/locked/disabled endpoints and noneditable owners cannot enter the group.
A read-only inspected edge can still reveal other eligible edges with that name.
Empty names, unrelated anchors and empty eligible groups remain unavailable.

Freeze the group in the action target. Source, document, selection and constraint
epoch checks reject stale dispatch and actor application, including ABA, Undo,
replacement and another window. Endpoint and bone-group selection are transient;
no archive write, Undo transaction, preview revision or document publication occurs.
Repeated selection of the same group is a selection-epoch no-op. Cancellation is
checked before atomic publication using the existing session boundary.

Four model/session and two controller contracts cover exact Unicode/case/spacing,
owner/endpoint eligibility, readonly source inspection, exact bytes/history/redo,
stale and initially unavailable intent, window isolation and cancellation. Native
services in controller fixtures are blocked. Existing inspector contracts remain.
This implements stored bone-edge selection; generated bone hierarchy, batch rig
assignment, weights/deformation and physical keyboard/VoiceOver acceptance remain
open under M5. No core pin, dependency, native algorithm or quarantine change.
