# ADR 0035: Native component multi-selection and grouping

Status: Accepted

## Decision

Keep one window-local Set of selected component identities in the pure editor state. Node, edge, part and component selection remain exclusive. The single-component inspector and sibling-order actions are available only when exactly one component is selected. Selection changes never alter archive bytes, revision or history. Publication prunes missing identities; Undo does not revive transient selection.

Bind the native sidebar List to that Set and show a count for multiple selections. Its accessible actions menu exposes Group Selected Components for nonempty siblings under a supported parent, and Ungroup Selected Component for one supported group containing retained child XML. The existing document commands revalidate the operation on the editing actor. Grouping allocates a fresh UUID and selects the result atomically; ungrouping prunes the removed wrapper. Each edit publishes once and regenerates the mesh without resetting the camera.

Grouping one component remains useful for creating a named assembly. Grouping and ungrouping intentionally change entity settings as described in ADR 0034; exact Undo restores those settings. Collapsed descendants remain selected until an explicit selection change, matching persistent selection independently of visibility.

## Scope and verification

No dependency or engine change. Reparent destination selection, modifiers, drag-reordering and full Qt differential acceptance remain separate work under #62. See [verification](../component-grouping-verification.md).
