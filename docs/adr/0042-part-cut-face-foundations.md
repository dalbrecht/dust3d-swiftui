# ADR 0042: Part cut-face and rotation foundations

Status: Implemented for review. Tracks #83 and M3 #62.

Model built-in Quad/Pentagon/Hexagon/Triangle presets and linked profile parts
with typed immutable metadata and separate document/controller commands. Preserve
exact source profile identities: inherited UUID-shaped classification and exact
archive lookup are already shared by CutFaceLinks and profile transfer/cleanup.
Do not normalize IDs through Foundation UUID. A new link must target an existing
part with an engine-compatible identity. Validate the new part/node dependency
after the isolated XML mutation, before publishing: a path from the target back
to the edited owner creates a new cycle. Presets and independent links remain
usable despite unrelated imported cycles. Imported unresolved links can
still be inspected/preserved. Any existing part can supply a profile, as in the
inherited setter; do not implicitly change its target, nodes or other settings.
The engine's existing fallback for insufficient profile points is unchanged.

Absent/empty cut face means Quad. Unsupported text (including a bare UserDefined
marker without a linked identity) stays unavailable until explicitly replaced.
Rotation uses inherited normalized half-turns in -1...1; one equals 180 degrees.
Absent/empty rotation means zero. Reject invalid ranges, nonfinite and subnormal
new values, preserving unsupported source values. Also reject a nonzero Double
that becomes zero or nonfinite in the generator Float; finite output alone does
not prove that the requested parameter was applied. Extract EngineScalar from the
previous deformation implementation with package visibility so document and
controller inputs share the tested source underflow policy and inherited
comma-decimal compatibility without adding
dependencies or framework imports to the helper.

Write every nondefault rotation, including values smaller than the inherited
writer's 0.01 omission threshold. Remove Quad/zero defaults on actual changes;
semantic no-ops retain original spelling, bytes and redo, including an unchanged
imported profile identity whose target is currently absent. New links still
require an existing target. Preserve node overrides,
part metadata, graph, assets, locks and camera/selection. Each controller edit is
one atomic history transaction with regenerated preview. Invalid input or newly
introduced profile cycles publish no partial state.

This stage has no native inspector controls. Rendered interaction, native
Save/Undo/Redo, keyboard/VoiceOver and Qt differential acceptance remain explicit
follow-ups. No C ABI or new package dependency is introduced. Comma-decimal
compatibility uses the native boundary fix in [core PR 6](https://github.com/dalbrecht/dust3d-core/pull/6),
merged after clean automated review and all six hosted jobs. The coordinated
exact pin is `7d37f08299dffb6e1c9d848bea3ee974169449b9` in both SwiftPM files. The
Apple repository keeps a single engine implementation in the maintained core.
