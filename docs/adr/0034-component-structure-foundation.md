# ADR 0034: Structural component commands

Status: Accepted; native structural controls follow separately

## Decision

Add explicit document commands for grouping siblings, ungrouping an unlinked group, and reparenting one subtree. Use the inherited document component operations as the semantic reference: grouping wraps selected siblings; ungrouping promotes children at the removed group's position; reparenting appends at the destination. Native grouping uses source sibling order rather than caller/Set iteration order, so nonconsecutive selections are deterministic.

Grouping requires a nonempty unique sibling set and a fresh bounded component identity that cannot collide with any supported semantic node/edge/part/component identity, including braced/unbraced UUID aliases. It inserts an unnamed group at the first selected sibling's slot; later selected siblings join that group in source order. Unselected siblings and opaque XML stay in source order. Grouping followed by ungrouping is not an inverse for nonconsecutive selections: their children become contiguous. Undo, rather than another structural edit, restores the exact prior archive.

An unlinked group has empty/absent link kind and data. Part-linked and opaque-link components cannot be destinations, parents receiving grouped/promoted children, or ungroup targets, but can move intact as subtrees or be wrapped in groups. Empty unlinked ungroup targets are byte-identical no-ops, matching upstream's empty-child behavior. Ungroup explicitly removes the selected group's identity and attributes/settings; all child XML is promoted, including opaque child data. Its undo restores removed group metadata exactly. This is an intentional entity edit, not a destructive save migration.

Reparenting validates destination identity and the entire ancestor chain before detaching XML, rejecting self/descendant cycles. Same-parent moves retain original bytes/redo. Old empty groups remain preserved rather than being implicitly pruned. Existing XML byte/depth/element limits and the 10,000-component limit apply; over-depth output fails before a new archive can publish. Unsupported node geometry remains opaque on these hierarchy-only document paths; editable sessions retain their graph-open validation.

The XML adapter pairs each immutable component value with its element from the same validated preorder before mutation. Document/session updates publish only after the full command or batch succeeds. Part state flags do not block structural hierarchy operations, consistent with the inspected upstream operations. Geometry combination may change, so future native UI actions must request preview regeneration.

## API and sequencing

`EditorSession.groupComponents(_:)` allocates a fresh UUID inside the actor and selects the resulting group in the same atomic update. Ungroup/reparent use the existing session apply API. Deleted group selection is pruned and does not revive through Undo. Root groups, nested groups, unknown metadata/assets and exact history are tested, with pinned-engine disjoint-union geometry checks.

This PR establishes the document/session contract. Native multi-selection, Group/Ungroup actions, a searchable destination picker and stale-draft handling follow in the next reviewed stage under #62. Modifier/Qt differential acceptance remains open. No dependency, core pin, C++, CI or lockfile changes.

See [verification](../component-structure-foundation-verification.md) for measured coverage and engine/history evidence.

## Review hardening

Shared `DocumentXML` helpers now own semantic traversal and inherited namespace preservation, reused by clipboard and structural commands. Components are traversed by qualified tag name so retaining a different default namespace does not hide moved children from hierarchy queries or reordering; prefixed extension tags remain opaque. Before ungroup/reparent detachment, preserve inherited default/prefix bindings that differ at the destination, including bindings used only by QName attribute values. Redundant destination bindings are omitted to retain ordinary net-zero transactions.

Structural namespace materialization is capped per operation at 100,000 added bindings and 16 MiB of prefix/URI payload plus a per-binding allowance. Existing encoded-model limits still apply. Expansion failures throw `limitExceeded` without publishing partial XML. Clipboard's existing default namespace policy is retained by the shared helper; this change does not claim whole-app resource hardening.
