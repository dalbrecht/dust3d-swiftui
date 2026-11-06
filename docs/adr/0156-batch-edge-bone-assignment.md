# ADR 0156: Atomic captured bone assignment for explicit edges

Status: Implemented; full gate and physical acceptance tracked separately

## Decision

Match Qt BoneManageWidget::assignSelectedEdgesToBone: explicit selected edges
receive one exact stored name and one snapshot. Native graph-selection controls
now share the single-edge editor, including Apply, explicit Clear/Clear All and
Reset Draft. Selected nodes never infer adjacent edges. A mixed blank field does
not clear existing assignments without an actual edit or explicit Clear action.

Use one setEdgeBoneNames document command. Validate the name once, preflight all
requested exact IDs and eligibility, then traverse/edit one owned XML tree.
This avoids repeated archive decoding/encoding for each selected edge. Preserve
original errors, opaque assets, unrelated metadata/edges and exact Undo/Redo.
Metadata classification preserves geometry/material preview identities. Legacy
absent edge owners retain single-edge behavior; assigned owners and endpoints
must be supported/editable. Unsupported aliases and any readonly member reject
the batch instead of silently dropping members.

The target freezes explicit IDs and all source/interaction epochs. Controller
factory and serial session reject stale/unavailable intent, including ABA, Undo,
replacement, stop and another window. Cancellation is checked before atomic
publication. No-op values do not create history or document publication.

The view resets its draft when target epochs change, while retaining the native
text-field identity. Unrelated publications preserve the caret; accepted
byte-distinct source names reset exact text. Keep the native field's Escape and
Return behavior. The existing single-edge controller API remains for immediate
callers; UI controls dispatch captured actions.

TDD covers document, model/draft/session and actual controller factories. The
existing native field/caret/Unicode regressions also pass after reuse. Native
services in new controller fixtures are blocked. No generated rig, pose/animation
evaluation, dependency, native algorithm, core pin or quarantine changes. Full
bone hierarchy, weights/deformation, physical keyboard/VoiceOver and M5/HIG
acceptance remain outstanding.
