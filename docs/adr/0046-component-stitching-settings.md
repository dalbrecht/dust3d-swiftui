# ADR 0046: Component stitching settings

Status: Accepted for the native editor prototype.

Expose inherited frontClosed/backClosed/sideClosed flags, targetSegments and
backCloseDepthRatio/backCloseSharpness as a cohesive, immutable component
settings value. Known defaults are false, automatic zero, depth one and
sharpness zero. Unknown flags and ambiguous/empty numeric metadata remain
unavailable until explicit replacement. Use strict whole segment counts in
0...100 and the existing engine-compatible scalar parser for depth 0...2 and
sharpness 0...1, including comma decimals and Float underflow protection.

Typed lossless commands reuse session history and actor generation. Defaults
remove only a changed attribute; semantic no-ops retain source spellings and
redo. Nodes, links, flags, opaque XML and assets survive. Native controls appear
on supported group components and do not interpret unknown link kinds.
Closure choices apply immediately; numeric drafts require Apply/Return and reset
on source, component or document identity changes. Reset Draft never edits.

Test configured curved stitching-line profiles, concentric closed loops, numeric
boundaries, exact undo/redo and error retention through the pinned core. Side
closure joins each spline's own endpoints, so straight closed rails are retained
as a degenerate rejection fixture rather than used as valid surface input.
No geometry guard is weakened and no second engine adapter is introduced.

Share the hidden-window inspector renderer across part/component suites. Export
synthetic light/dark artifacts for inspection without desktop interaction or
product launch. No snapshot baseline is committed. Static rendering does not
establish native input, VoiceOver, GPU or agreed Qt geometry tolerance parity.
