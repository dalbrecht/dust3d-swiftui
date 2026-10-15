# ADR 0007: Marquee selection and centroid scaling

Status: Accepted for the editor prototype.

Marquee selection uses a direction-independent rectangle in canvas points and selects visible node centers, including boundary points. Hidden nodes stay excluded; visible read-only nodes can be selected for inspection. A plain background drag replaces selection, Shift-drag adds to it, and clicking empty background clears it. These operations change only per-window selection. A gesture-state rectangle clears automatically on cancellation; node dragging remains a separate hit target above the background.

Group scaling accepts independent positive, finite factors for positions and radii. Positions scale about the arithmetic mean of editable selected node positions. This follows the origin-average center in the inherited `SkeletonGraphicsWidget::centerOfNodeItemSet`; this inspector uses explicit factors rather than Qt's wheel delta. Read-only nodes are excluded from both the transform and its center. Locks retain individual fields and skip their arithmetic before geometry validation, so a large factor in a locked field cannot prevent scaling an unlocked field. Scaling uses the bulk command boundary, validates before publication, and records one undo step. Factor 1 bypasses position arithmetic so roundoff cannot dirty a document during an identity transform.

Rectangle geometry/projection and scaling stay in the framework-free editor model. The SwiftUI layer owns gesture state, modifier routing, rectangle drawing and inspector controls. No native core API or dependency change is needed.

This does not establish full Qt interaction parity: edge selection, wheel transforms, rotations, flips, clipboard and graph part splitting/merging remain separate work. Shift-drag routing needs a direct manual pass because the current UI automation API cannot hold a modifier-only key during a drag.
