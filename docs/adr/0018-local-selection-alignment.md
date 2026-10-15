# ADR 0018: Local alignment through selection transforms

Accepted 2026-10-15. Tracks #37, the local alignment stage of M2.

Extend the existing `SelectionTransform` value and shared actor/state command rather than add a parallel alignment history path. Offer explicit Front X, Front Y, Front X/Y, Side Z, Side Y and Side Z/Y choices in the existing Canvas/inspector transform menus. Explicit axis labels avoid ambiguity about horizontal/vertical center and remain independent of the currently displayed projection.

Replace the requested coordinates with the arithmetic mean of editable selected-node positions; retain other coordinates and radii. This follows the unrotated Qt local-center arithmetic (`SkeletonGraphicsWidget::alignSelectedToLocal` and `centerOfNodeItemSet`). Continue the native editor's existing editable-centroid policy: selected hidden/locked/disabled nodes remain untouched and do not bias the center. Qt's merged visual-selection set is not asserted to be identical for every mixed-profile/readonly selection. Axis locks constrain requested changes through the existing transform path; radius locks are naturally unaffected. Empty/readonly/single/already-aligned selections are semantic no-ops and preserve redo.

Each action is one existing atomic set-nodes transaction with exact archive undo/redo and unchanged selection. Bounds remain stable during geometry editing. No C++/core pin/new dependency change is needed. Alignment can intentionally create coincident geometry; the existing last-valid-preview/error handling applies rather than silently changing topology or coordinates. Origin/global alignment and descendant-pivot rotations remain separate tools.
