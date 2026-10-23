# ADR 0092: Lossless edge bone bindings

Status: local implementation, #247, part of M5 #144.

## Context

The reference Document::setEdgeBoneName stores an edge string; toSnapshot emits
nonempty boneName and loading restores it. The inherited rig generator looks up
those exact names to associate model-edge endpoints with bones. Binding is stored
intent, distinct from accepted native bone generation or normalized weights.

## Decision

Expose the exact name in DocumentEdge and add setEdgeBoneName to the existing
immutable document command API. Empty clears the attribute. New names have a
1024-UTF-8-byte limit and reject control/newline/invalid XML characters. Preserve
leading/trailing spaces and case because normalization could retarget identity.
Reads retain all legacy spellings without rewriting or enforcing new-edit limits.

Both endpoints must satisfy the existing editable-part rules, as with edge removal
and reversal. Missing/read-only targets reject atomically with invalidNode; invalid
names use invalidBoneName and an explicit editor message. Preserve every unrelated
XML attribute, rig child and opaque archive item. Existing session batch/history
and immutable edge snapshots carry the command without another state store.

## Validation and limits

Tests first failed on the missing field/command. Focused tests cover exact/empty/
legacy names, XML escaping, Unicode byte limits, forbidden scalar values, independent
read-only endpoints, no-op redo, exact history/reopened storage, unknown XML/assets,
atomic session rollback and retained selection/locks. One initial test incorrectly
assumed ImportedModel metadata alone made a part read-only; inspection established
that inherited editor visibility/lock/disabled flags govern editability. The fixture
was corrected to those rules, without changing target-role editing policy.

No native evaluator, pose, animation, GLB or quarantined API is called. No core pin,
dependency, CI, renderer or visible binding control changes. Actual bone existence,
weights, deformation and native interaction acceptance remain separate M5 gates.
