# ADR 0091: Lossless stored rig parameters

Status: local implementation, issue #246, part of M5 #144.

## Context

The reference `Document::toSnapshot` writes canvas `rigType` and optional true
`headHasEyelids`; loading reads the template string and String::isTrue boolean.
The seven retained `application/resources/rig_*.xml` templates declare Biped,
Quadruped, Bird, Fish, Snake, Insect and Spider. None/empty disables generation.
These source facts do not establish a safe native evaluator or accepted rig UI.

## Decision

Expose immutable DocumentRigSettings, recognized DocumentRigType and exact original
sourceRigType. Unknown template strings remain unsupported intent rather than
silently becoming disabled. Match inherited eyelid truth semantics while keeping
all source bytes on read/no-op. Typed template and eyelid commands edit only the
named canvas attribute; snapshot history provides exact undo/redo. A genuine false
eyelid edit removes the attribute, matching reference serialization.

No engine call occurs. Keep unsupported rig/bone/animation XML and every archive
item intact. The API deliberately does not return generated bones, weights, pose
or a native-support flag. Core/Apple quarantines and the production pin are unchanged.
No dependency, renderer, UI, CI or lockfile change is required.

## Validation and remaining work

Tests first failed because the API/commands were absent. Pure tests cover all
seven templates plus disabled, absent/empty/unknown/case-sensitive source intent,
inherited boolean spellings, opaque assets, unrelated XML, exact history/no-op redo
and reopened storage. The full gate is required before publication.

This is one M5 persistence stage. Native template controls must expose actual engine
capability and must not accidentally invoke quarantined evaluation. Bone ownership,
axes/units, parent graphs, weights, skeleton picking, IK, rest/deformed poses and Qt
fixture comparisons remain unimplemented or unaccepted follow-up work.

## Editor snapshot integration

DocumentContents decodes rig settings during its existing canvas parse;
EditorSnapshot copies that value from the same accepted contents. There is no
additional per-gesture XML parse or UI-thread derivation. Existing session batches
publish parameters atomically with graph metadata, preserving selection and locks.
No separate rig state store is introduced. Regression tests first failed on the
missing snapshot property, then verify one-step batches, no-op revisions/redo,
rejected-batch rollback, independent sessions and replacement freshness. These
pure tests make no engine or pose call.
