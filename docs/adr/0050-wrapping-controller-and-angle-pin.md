# 0050 — Wrapping controller and bounded-angle core pin

Status: Accepted for controller integration; native controls follow separately.

## Context

ADR 0049 added lossless document commands. The inherited inverse-cosine input
could round outside [-1,1], causing Cloth openings and straight-profile generation
to report nonfinite normals. Core PR #15 fixes that calculation and changes which
fixtures correctly represent genuine generation failures.

## Decision

Pin core exactly to reviewed `4e49670e6819f996ddac1a2befb6f23d72154341`, including
the generated resolved file. Keep all engine implementation in dust3d-core.
Connect mode, keep-children, scalar and face-count edits to the existing
EditorStore → EditorSession → immutable document command pipeline. Parse drafts
with the shared finite Float-compatible scalar parser and whole face bounds.
Stopped/busy stores reject drafts before parsing; generation remains serialized
off the UI actor and obsolete preview requests retain their existing guards.

Update numerical regression expectations: the .225 midpoint openings and straight
profiles now require finite output. Do not preserve an old rounding failure as a
validation rule. A finite negative legacy wrap offset that removes the entire
surface remains the genuine generation-failure fixture. It proves that status 3,
the original diagnostic and the previous stale mesh remain distinct from status 5
successful empty output. The native C ABI finite-output guard remains intact.

## Consequences and limits

Controller tests exercise real pinned-core output, comma drafts, invalid edits,
selection/camera preservation, exact history, save publication and stop behavior.
Allow a 30-second bounded async settle window because wrapping can take several
seconds even for a small document; no mesh work is moved onto the main actor.

Native controls and pointer/keyboard/GPU acceptance remain pending. Core issue
#14 separately tracks zero-area/collapsed wrapping and straight-profile faces;
finite normals do not establish topology or Qt differential parity. Binding and
material controls remain later work. No new dependency, adapter or CI changes.
