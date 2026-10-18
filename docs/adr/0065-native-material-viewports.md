# ADR 0065: Native material preview adoption

Status: implemented for Apple #131; full local gate and native checks pass, automated review pending.

## Decision

Use the shared production material encoder in the existing `MeshViewport`, retaining
ordinary indexed geometry for immediate display and optional-material failures.
The view owns a cancellable upload request and transfers fresh actor-built GPU
resources only for the current revision. Rotation/zoom/fit and wireframe remain
continuous across ordinary/material transitions. The ordinary renderer remains
available as fallback, so logical GPU quotas do not claim a whole-process memory
cap. Dismantling cancels upload and detaches the draw delegate.

Native apps request bounded preview maps (512 color/atlas, 256 normal, 128
material/emission), independently of source image dimensions or archive bytes.
Baking and GPU upload run on background actors. Original source PNGs and all
unsupported archive items remain untouched; preview resolution is not export
resolution. The inherited baker still regenerates geometry; incremental material
baking and performance tuning remain subsequent work.

The editor starts material work after successful current ordinary geometry. A
separate request state invalidates on edits, undo/redo, replacement, empty output
and stop. Material-only edits explicitly refresh without incrementing the
ordinary geometry revision. If such an edit arrives while geometry is pending,
its completion starts baking from the current document snapshot. Revision-paired
baked geometry/maps are never attached to a different ordinary mesh.

The viewer reads one bounded file snapshot for both ordinary geometry and later
baking. It never reopens a potentially changed file to resolve materials. File
replacement, retry and stop cancel prior work; identity guards reject late
completions even if an underlying operation ignores cancellation.

Optional material failures preserve ordinary geometry and show the original
cause with an explicit Retry Materials action. GPU failures similarly return to
ordinary geometry. Material work never commits document edits or undo entries.
System progress, caption typography, semantic warning colors and native buttons
follow the existing SwiftUI styling system and make-interfaces-feel-better's
restraint for frequent updates; no decorative transition or new styling system
is introduced.

## Acceptance and limits

See `docs/native-material-viewports-verification.md`. This stage adopts the five
reviewed maps; it does not establish AO, image import controls, embedded-model
support, exports, environment IBL or full Qt material parity. Atlas-wide alpha
routing and triangle-centroid transparency limits from ADR 0064 remain.
