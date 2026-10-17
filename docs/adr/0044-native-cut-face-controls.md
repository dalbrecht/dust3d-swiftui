# ADR 0044: Native cross-section profile controls

Status: Accepted for the native editor prototype.

Expose the reviewed cut-face commands through a preset menu, a searchable
linked-part chooser, and a half-turn rotation draft. The menu retains a current
linked selection, including unresolved imported IDs, and an explicit unsupported
source state. It does not normalize unknown metadata when presented.

The chooser searches names and exact identities, excludes the inspected part and identities the engine cannot link,
and uses lazy rows in a bounded scroll region rather than a menu containing up
to 10,000 parts. A row is an immediate choice, so there is no deferred profile
selection that could later apply to a different document. The current command
path validates existence and dependency cycles atomically; rejected links retain
the document and history. Duplicate names retain distinct identity labels and
full help/accessibility descriptions. Search resets on inspected-part/document
identity changes. Roles and broader profile modeling remain separate M3 work.

Rotation uses the existing parser and −1 through 1 range. Apply or Return is one
command; Reset Draft only restores the source interpretation. Rendering and
state/history preservation use the hidden-window QA exporter established in ADR
0043. Native input, VoiceOver and GPU checks remain explicit acceptance gaps.

The document model exposes the command's existing identity classification so
the UI does not duplicate or tighten inherited UUID-shape rules. Candidate
filtering lives in the pure editor model and preserves source spellings.

The pure menu projection includes an unsupported placeholder only for unknown
source metadata. The placeholder is disabled; supported profiles offer only
presets and the current linked identity, without an enabled no-op choice.
