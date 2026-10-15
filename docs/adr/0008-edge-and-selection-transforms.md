# ADR 0008: Edge reversal and basic selection transforms

Status: Accepted for the editor prototype.

Reverse edges through a bulk document command that swaps only `from` and `to` on existing edge XML elements. Preserve IDs, part references, unknown attributes, child XML and all archive assets. Validate duplicates, missing edges and read-only endpoints before publication. A selected-node group reverses only edges whose two endpoints are editable and selected. The single-node inspector also exposes each incident edge's direction and its Reverse/Disconnect actions. This provides reversal without claiming explicit edge picking or edge selection is complete.

Provide fixed 90-degree clockwise/counterclockwise transforms in Front (X/Y, around Z) and Side (Z/Y, around X), flips on X/Y/Z, and X/Z exchange. Fixed quarter turns use coordinate exchange/signs rather than trigonometric approximations. The editable selected-node centroid supplies the pivot; read-only nodes are excluded from both pivot and changes. Geometry changes retain radii, selection and unrelated metadata, validate bounds atomically, and take one undo step.

The source oracle is `application/sources/skeleton_graphics_widget.cc`: `rotateSelectedAroundZAxis90Degree` and its negative/X counterparts, `centerOfNodeItemSet`, and flips. These axis transforms route through `Document::moveNodeBy` and honor movement locks. The native implementation restores locked components before validating derived geometry, avoiding rejection due to an out-of-range provisional value in a locked field.

`Document::switchNodeXZ` in `application/sources/document.cc` directly exchanges X/Z without interaction locks. Match that explicit command while retaining part read-only protection and leaving lock settings unchanged. The menu says “Exchange X/Z (ignores axis locks)” so the exception is reviewable to users. Other new transforms honor locks.

No C++ or engine ABI change is needed. Native commands, pure transform geometry and archive mutation retain their existing module boundaries. Explicit edge selection, descendant-pivot rotation, alignment, clipboard, reference images and Qt graph split/merge semantics remain separate parity work. No complete M2 or full Qt parity is claimed.
