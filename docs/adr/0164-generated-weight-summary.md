# ADR 0164: Numerical selected-joint weight summary

Status: Experimental local-core preview follow-up, Apple #367 / M5 #144.

The rest preview's weight colors need useful numerical text alongside them.
Summarize the selected joint's raw minimum/maximum weight across admitted body
corners and count body triangles with any positive selected influence. Each
triangle counts once, regardless of how many corners are influenced. Do not
present duplicated draw corners as original mesh vertices; skeleton geometry is
excluded. These values supplement the color view, not a full spatial/per-vertex
weight inspector or physical VoiceOver acceptance.

GeneratedRig.weightSummary uses exact UTF8 joint names and sums all four slots.
Empty/unknown selection returns nil. Copied mesh/influence correspondence,
finite weights, zero-slot sentinel and source indices are validated with the
same Double total-weight tolerance1e-4 as native copying. Preserve admitted raw
values rather than clamping; tiny positive influence still counts. Typed localized
errors retain the failing invariant. Poll cancellation before lookup, per1024
corners and before returning. No C entry point or document write is involved.

The detached display worker prepares mesh and summary from the same immutable
rig/request, then publishes both in one main-actor segment with the accepted
request assigned last. Prior values may remain stored during refresh, but the
view hides them on key mismatch, loading or error. Replacements and stop retain
the existing epoch guards; stop clears the summary. Numerical Text views combine
for accessibility without replacing their contents with a generic group label.

TDD missing helper/state RED70038; GREEN35445 passes45 focused tests, including
eight helper tests and atomic publication/stale-result coverage. Measured helper
coverage61/62 lines (98.39%),43/44 regions (97.73%),5/5 functions; display99/99
lines,35/35 regions,13/13 functions. The selected Int-to-UInt32 overflow error
would require over four billion source joints and is not forced with an allocation
or exhaustion probe. Existing injected fixtures were made coherent rather than
relaxing source validation. Independent source review found no concrete defect.

The isolated experimental run41338 compiled the numerical SwiftUI surface and
passed51 scoped tests on f2d32d44. A subsequent change only wraps one long test
assertion and records this result; production Sources remain identical. The full
production gate initially stopped at that strict formatting check, before tests;
formatting now passes and the complete gate remains required. PR369's reviewed
head remains unchanged while its native checks run. Production core
pin, QA52 default, quarantines and protected QA process are unchanged. No GUI,
pose, animation, GLB, writer or broad core-catalog runtime probes are added.
