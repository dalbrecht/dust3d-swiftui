# ADR 0005: Interaction locks belong to editor sessions

Status: accepted, October 14, 2026.

The Qt editor stores xlocked/ylocked/zlocked/radiusLocked as document interaction
settings, outside its serialized modeling snapshot. Its movement/radius setters
honor these flags; node creation and history restoration are separate operations
(`application/sources/document.cc`, createNode, moveNodeBy, setNodeOrigin,
setNodeRadius and lock setters).

Keep a set of EditingConstraint values in each EditorState, surfaced through the
immutable snapshot and serialized by its EditorSession actor. Changing a lock
must not write archive bytes, change revision, add history, clear redo or generate
a new mesh. Both direct and batched node setters validate numeric inputs and
part editability before preserving locked fields. Undo/redo restores snapshots
without reapplying movement locks. New nodes and graph topology remain governed
by their own commands and part readonly checks.

Use the same constraints in CanvasProjection for the temporary drag position and
the committed command. SwiftUI controls expose lock state and disable corresponding
inspector fields. Reset newly locked draft fields to their committed values;
unrelated drafts remain local until Apply. Scope Canvas menu commands to the
focused scene and use Command-Option shortcuts to avoid plain-text/clipboard keys.

This adds no persisted schema, preference file or dependency. A reopened document
starts unlocked; different windows remain independent. Full modeling constraints
and part/component inspectors remain later milestones.
