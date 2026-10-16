# ADR 0033: Component sibling order

Status: Accepted; see verification and remaining parity limits

## Decision

Implement Up, Down, Top and Bottom as final-index moves among the selected component's current siblings. Parent identity and the entire descendant subtree remain unchanged. The inherited `Document::Component::moveChildUp/Down/ToTop/ToBottom` and corresponding document methods define these operations; unlike node transforms, these upstream ordering commands do not consult part visibility/lock/disabled flags. The native commands follow that behavior, while coordinate/radius constraints continue to apply only to geometry edits.

A pure bounded index resolver returns no target for invalid indices or already-reached boundaries. Component hierarchy interpretation validates identity/containers before mutation. The XML adapter reorders only component slots and preserves non-component sibling slots, including comments, whitespace and unknown elements. Archive assets and unrelated model fields remain unchanged. Unsupported tagged component identities reject rather than disappearing. Boundary moves preserve original bytes and redo history.

The inspector exposes a native Reorder Component menu, with unavailable boundary moves disabled. Availability comes from cached pure tree metadata and does not parse XML in view rendering. A real move is one atomic session transaction, retains component selection and regenerates mesh output: sibling order can affect boolean combination. Preview failure remains isolated from document publication, as for existing modeling commands. No artificial mesh-cache optimization is added before correctness.

The command interprets component hierarchy independently of unrelated unsupported node geometry, preserving that graph on the document API path. Editor sessions retain their existing graph-open validation. This is sibling order only; grouping, reparenting, ancestor lock semantics and the remaining modifiers stay open in #62. Qt numerical/GUI parity for modifier combinations remains acceptance work, not implied by basic union regeneration.

No dependency, core pin, C++, CI or lockfile changes.

See [verification](../component-order-verification.md) for automated and native save/history evidence.
