# ADR 0047: Isolated stitching-loop interior fill

Status: Accepted for the native editor prototype.

Expose the inherited fillLoopInterior flag as an optional known Boolean on the
immutable part metadata and a typed lossless command. Missing/empty is false;
unsupported text remains unavailable until replacement. True writes the flag,
false removes only a changed attribute, and semantic no-ops retain exact bytes
and redo. Nodes, roles, flags, opaque data and assets remain intact.

The engine's fillIsolatedLoops applies only to closed loops whose directed
boundary edges do not already participate in the stitched surface. Test both
an isolated loop (real geometry changes) and connected concentric loops (the
flag may change without affecting geometry). A separate uncombined model in
the isolated fixture keeps the overall scene nonempty when the loop is unfilled.
No behavior is inferred from a metadata-only assertion.

Show the native control only for StitchingLoop roles, with an isolated-loop
label and explanatory caption. Unknown source values use a disabled placeholder
and explicit On/Off choices. Commands reuse the actor/controller history path.
Use the existing hidden-window QA exporter for static rendering. Native input,
VoiceOver, GPU and Qt differential acceptance remain pending.

This does not implement hollowing: the legacy hollowThickness attribute has no
consumer in the current core generator, tracked separately as #96. Preserve it
and keep the full plan's hollowing requirement open until implemented/proven.
