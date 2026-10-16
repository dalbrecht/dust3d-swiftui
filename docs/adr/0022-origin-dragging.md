# ADR 0022: Explicit, guarded origin gestures

Accepted 2026-10-16. Tracks #45; extends ADR 0021's display-only marker.

Use an explicit per-window Move Origin mode. The marker remains hit-transparent outside that mode, including where it overlaps a node. While active, node/marquee gestures are disabled and the marker has a 44-point hit target. The existing origin coordinate inspector remains the accessible keyboard alternative. Escape, mode exit, projection/viewport change, Fit, document operations, replacement and window teardown discard the transient draft. Completing a drag exits the mode.

`OriginDrag` captures immutable origin, axis locks, projection, open-document identity, document revision and constraint revision. Total screen translation always projects from that baseline; previews never write archive/history. A monotonic constraint revision prevents a lock-on/lock-off cycle from reviving an obsolete gesture. Session commit checks these guards on its actor before applying one validated `.setOrigin` command. Invalid finite/bounds inputs reject atomically; radius locks and readonly parts do not constrain this document-global operation. A no-op creates no undo entry. Cancellation preserves redo.

Committed origin changes use the existing debounce/request identity preview policy and canvas-only fit, preserving mesh orbit. No C++ or dependency change is needed. Opening the same bytes starts a new identity even though document revision resets to zero. Fit/reference-image-driven refits cancel the draft rather than changing its coordinate system mid-gesture.

Qt's `Document::moveOriginBy` adds the delta to the stored origin and applies X/Y/Z locks when its position-lock gate is enabled; it does not apply per-part readonly flags. The native Front projection maps X/Y and Side maps Z/Y, with positive Y down, and always applies active window axis locks. This stage operates in unrotated document planes; rotated/mixed-profile differential fixtures remain pending. Native explicitly stored zero origins stay valid, unlike Qt's fuzzy-zero settlement predicate. No automatic bounding-box settlement or rotated-view behavior is introduced.
