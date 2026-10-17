# ADR 0036: Inline component parent selection

Status: Accepted

## Decision

Offer Move to Parent in the single-component inspector as an inline, searchable destination list. Root is explicit; supported groups follow document order. Exclude the source, its entire subtree, its current parent and unsupported links. Match both names and stable IDs without mutating the document. Keep Cancel, Reset and Move visible rather than introducing another modal sheet.

Capture document identity, monotonic document revision and the selected component when the chooser opens. Revalidate that target on the editing actor before applying the existing hierarchy command. Document replacement, an intervening edit (including Undo) or a different/ambiguous selection rejects atomically with a typed stale-target error. Group eligibility, cycles, namespaces and archive limits remain enforced at the document boundary. Locks remain orthogonal to hierarchy edits, consistent with prior grouping/ordering behavior.

Move appends the complete subtree in one undo step, preserves selection, regenerates the preview and leaves the camera alone. Reset clears the query and chosen destination against the current snapshot. Cancel edits nothing. The selectable parent-identity text has an identity keyed to its parent, so native accessibility text is recreated when that parent changes.

No new dependency, engine ABI or document format change. This completes the initial native grouping/order/reparent controls, not component modifier or full Qt parity. See #62 and the [verification record](../component-reparent-verification.md).
