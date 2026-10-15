# ADR 0021: Noninteractive canvas origin and shared fit bounds

Accepted 2026-10-15. Tracks #43, the origin-display stage of M2.

Render the supported stored origin in Front/Side using the same projection as nodes, with a native scope symbol, a short Origin label and accessible coordinate values. Do not add a new selection/gesture mode: the marker ignores hit testing, and node handles retain their existing selection behavior even when centered on the origin. Unsupported/missing origins have no marker; the inspector remains the explicit initialization boundary.

CanvasBounds optionally fits the origin together with visible node radii and the reference-image rectangle. Ignore nonfinite/out-of-bound public origin inputs consistently with the document reader. Empty scenes retain the existing unit/reference bounds and include an outlying supported origin. Hold bounds stable during node movement, but recompute canvas-only bounds when the stored origin changes, including Undo/Redo; preserve the 3D orbit-camera reset token. Explicit Fit and topology-count changes keep their existing combined-fit behavior.

Move blank-canvas help to the bottom so it does not crowd the origin marker. Marker display, projection changes, selection and Fit remain transient; the only serialized operation is an explicit origin edit through existing history. This stage adds no dragging or automatic settlement and changes no core/C++ dependency.
