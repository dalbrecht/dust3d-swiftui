# ADR 0027: Qt clipboard text adapter

Status: Accepted

## Context

Inherited `Document::copyNodes` writes `saveSnapshotToXmlString` output into QClipboard text. `Document::paste` passes that text to `loadSnapshotFromXmlString` and `addFromSnapshot`. The serializer uses a canvas root with nodes, edges, parts and nested components. The native transport adds selected-node metadata and a full asset-bearing archive, so replacing it with plain XML would lose information.

## Decision

Keep the native representation first in the SwiftUI Transferable declaration. Add UTF-8 plain text as an import alternative. Copy/Cut publish both representations from one immutable fragment prepared on the session actor. The AppKit provider serves each requested type separately; it never serves native binary bytes as text. Register both promises before Cut deletes anything. Native field editors retain their existing responder routing.

`Dust3DDocument(snapshotXML:)` wraps at most 16 MiB of exact UTF-8 model XML in an asset-free archive and reuses existing XML/depth/entity and editable-graph validation. `NodeClipboardPayload(snapshotXML:identifier:)` adds the stricter clipboard identity, part/profile and topology validation. All contained nodes are selected because Qt text has no explicit/dependency selection distinction. Invalid/empty clipboard graphs reject atomically.

Both inputs use the same paste normalization, fresh IDs, construction splits and one-step undo transaction. The session retains the most recent successful XML/token pair (bounded by the input limit), comparing exact bytes to advance repeated-paste placement without hash collisions. Failed pastes do not replace this pair. Open clears it. Identical text recopied externally is treated as the same source until another successful XML paste or Open; plain text has no Copy token.

## Limits

Plain XML contains no embedded asset bytes. Qt text transfers graph attributes and may retain references to assets unavailable in the destination. Only native transfers promise asset and explicit-selection fidelity. Menu help exposes this distinction. No import fabricates assets, strips unknown fields or claims full Qt GUI interoperability. Legacy snapshot schemas, branching topologies and missing-asset editing remain constrained by existing validation; do not relax engine assumptions as part of transport work.

No dependencies, core pin, C++ code or CI configuration change. Native interaction and Qt GUI evidence are recorded separately from pure and pinned-core tests in [verification](../qt-clipboard-verification.md).
