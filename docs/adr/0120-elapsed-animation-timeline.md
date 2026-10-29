# ADR 0120: Pure elapsed-time animation sample selection

Status: Proposed for #225.

## Decision

Keep sample selection in Dust3DEditorModel as an immutable, framework-free
projection over already-owned timestamps. Admit at least two finite strictly
increasing samples starting at exactly zero and ending at a finite positive
clip duration. Preserve nonuniform intervals rather than deriving an index by
multiplying duration and sample count.

Playback consumes elapsed seconds from a future clock owner. A binary upper-bound
search selects the latest sample at or before the phase. Nonlooping playback
clamps at duration and marks completion. Looping playback uses floating-point
remainder, avoiding an overflowing elapsed/duration quotient or unsafe integer
cast. Exact duration wraps to zero during playback; explicit scrubbing uses the
closed interval and can display the final sample of a loop. Invalid caller times
produce typed errors instead of silently resetting the playhead.

The timeline does not advance by callback count, mutate archives, allocate frames,
retain engine owners or evaluate animations. Clock ownership, pause/seek epochs,
source-scoped clip loading, audio synchronization and native playback controls
remain subsequent work. There is no production dependency or quarantine change.

## Verification

Pure XCTest covers irregular sample intervals, skipped ticks, exact boundaries,
loop wrapping, terminal scrubbing, finite large elapsed time and rejected sample,
duration and caller-time metadata. These are owned scalar/array fixtures, not
native malformed inputs, resource-pressure or native animation sampling probes.
No UI changes or new pixel baselines are introduced. Full M6 remains open.
