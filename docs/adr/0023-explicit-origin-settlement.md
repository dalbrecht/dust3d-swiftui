# ADR 0023: Explicit model-bounds origin settlement

Accepted 2026-10-16. Tracks #47; extends the document-origin tools without implicit serialization changes.

Expose **Center Origin on Model** in the origin inspector and Canvas menu. Compute the center of every document node's radius bounds on X/Y/Z, independent of selection, visibility, readonly/disabled flags, reference images or camera. Empty models target (0,0,0). `OriginSettlement.center(of:)` validates all supplied geometry before computing; it never writes document state.

The session routes the target through the existing `.setOrigin` command and history. Axis locks apply, radius locks and per-part flags do not. Initializing unsupported/missing origins still requires unlocked position axes. One operation is one undo step; a no-op preserves redo. Nodes, parts, unknown metadata and assets remain untouched. The app discards transient gestures, regenerates with its existing debounce/error identity policy and refits the canvas without resetting mesh orbit.

Reference: inherited `Document::resolveSnapshotBoundingBox` (`application/sources/document.cc`, lines 3085–3130 at 2901eac) unions all node positions ± radius; `settleOrigin` (3133–3148) centers those bounds. The native calculation matches that radius-bound rule using validated Double arithmetic. Qt uses float, runs settlement implicitly only when `originSettled()` fails its fuzzy-zero predicate, and calls setters bypassing interaction locks. The native command is explicit, always requests centering, accepts zero as a valid origin, honors active axis locks and never rewrites stored origins merely by opening/saving. These differences are deliberate, consistent with ADR 0020. Full rotated/mixed-profile GUI comparison remains acceptance work.

No new dependency, native ABI or C++ change is needed.
