# ADR 0017: Native part selection and state controls

Accepted 2026-10-15. Tracks #35, a bounded first stage of M3 part/component editing.

Expose immutable ordered `DocumentPart` values independently of nodes and component hierarchy. Preserve original IDs, unknown attributes/children and component names. A part's legacy `name` is separate from the linked component's name. Native naming edits trim outer whitespace, allow XML-escaped Unicode, cap input at 1024 UTF-8 bytes and reject controls/newlines. Empty input restores a generated sidebar label without writing that label to the archive.

Use the inherited `visible`, `locked` and `disabled` attributes. Visibility hides canvas overlays; locking blocks geometry edits; disabling additionally excludes generated geometry. Keep inactive and empty parts in the sidebar so their state can be restored. Part metadata controls remain available even when the part is hidden, locked or disabled. Node/edge/part selections are mutually exclusive, transient and pruned after graph changes; Undo restores document state without reviving invalid selection.

Apply each metadata change through existing immutable document commands/history. Preserve bytes for semantic no-ops. Normalize known boolean aliases/defaults only during model comparison so net-zero flag transactions restore exact original bytes and preserve redo. Ordinary part edits retain model-only comparison rather than scanning opaque assets. Only disabling needs preview regeneration; all-disabled documents clear derived output without a spurious empty-geometry error. Unassigned legacy nodes still attempt generation and surface the existing diagnostics.

Names/flags do not implement hierarchy, grouping, reordering, modifiers or component naming. No C++/core dependency change or relaxation of the core's graph validation is involved. Verify native flags/history/save behavior and multi-part engine output independently of tests for document preservation.
