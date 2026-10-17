# ADR 0038: Lossless component combine modes

Status: Accepted. Tracks #62.

Expose the inherited Normal, Inversion and Uncombined modes as a typed document
command and a native component inspector picker. Preserve component order: boolean
combination is ordered and this command does not reorder any siblings.

Read missing/empty mode as Normal. Interpret the inherited component `inverse`
flag only when mode is Normal, using the core's exact true spellings (`true`,
`True`, `1`). Unknown mode values remain unavailable metadata rather than silently
presenting Normal; unrelated commands continue to preserve them. An explicit
picker choice replaces the unknown source value. On an actual mode change, remove
component `inverse` so it cannot override a requested Normal. A semantic no-op
retains all original bytes, including legacy spellings, and does not discard redo.
This does not migrate legacy part-level inverse flags or change core parsing.

Use the existing serialized session command path, atomic history and preview
scheduler. Combination affects generated geometry, so regenerate on actual edits
without resetting camera or component selection. Editing-axis locks constrain
node transforms; as in the inherited component setter they do not lock component
combination metadata. No dependency or C++ change is needed.

Keep native control semantics simple: every picker choice is one undo step; there
is no unapplied draft. Show unsupported source mode until the user chooses a
supported mode. Test missing/ambiguous identities, opaque XML/assets, unknown and
legacy values, exact undo/redo, atomic batches and real pinned-core output.
Qt GUI differential acceptance and interacting modifier fixtures remain part of
M3; this stage alone does not prove full boolean/modifier parity.
