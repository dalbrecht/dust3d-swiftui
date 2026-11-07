# ADR 0151: Explicit ownership for connecting selected nodes

Status: Implemented; full local gate and physical acceptance tracked separately

## Decision

Expose Connect Selected Nodes in the multi-node and mixed graph inspectors and
the Canvas menu, using the existing document joinNodes operation. Metadata
admission requires exactly two explicitly selected, editable, assigned nodes with
spare degree, no connecting edge, no component or part selection, and room for
another edge. Existing edge picks do not supply endpoints and remain selected
after the join. UI metadata never parses XML or invokes geometry; complete
chain/profile validation stays in the existing document command, whose original
failures propagate without partial publication.

When parts differ, a native menu asks which part's settings survive. The payload
contains both document-ordered choices; it never derives ownership from Set
iteration. Same-part connections use the first document-ordered endpoint through
the same captured action. Existing joining code determines chain orientation.
Identical user part/node names receive exact node-ID suffixes so a destructive
settings choice remains distinguishable. SwiftUI menu identities use UTF-8 bytes.

CanvasAdjustmentTarget binds intent to document identity, document revision,
selection revision and constraint revision. Both controller dispatch and the
serial session reject stale intent, including ABA, replacement, other windows
and invalid owners. Owner lookup is byte-exact. A session allocates one fresh
edge UUID, applies one copied-state transaction, checks cooperative cancellation
before publication, and returns its committed snapshot. Controller delivery uses
the existing committed-cancellation policy, without a second publication.

No dependency, pin, C++, worker, rendering, export or quarantine changes. This
adds the direct selection workflow; it does not replace the one-node Connect to
menu or claim broad Qt topology, pointer/keyboard or VoiceOver acceptance.
