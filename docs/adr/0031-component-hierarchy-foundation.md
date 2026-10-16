# ADR 0031: Preserve ordered native component identity

Status: Accepted

## Decision

Expose component XML preorder as immutable `DocumentComponent` values, with parent identity, ordered direct child identities, name and raw link kind/data. The inherited `dust3d/base/snapshot_xml.cc` reads and writes nested components; flat part order cannot reconstruct that hierarchy. A part reference is interpreted only for the exact `partId` link kind. Unknown links and unreferenced/empty groups remain source data.

Hierarchy interpretation is an explicit `Dust3DDocument.components()` query. It rejects repeated component containers, absent/empty/duplicate component identities unsupported child tags carrying component identities and more than 10,000 components. Unknown child tags with IDs are generator inputs in the inherited parser, so the query rejects them rather than silently omitting them. Existing bounded XML parsing still limits size, depth and element count. Ordinary archive loading and unrelated editing retain their existing preservation policy: this query does not silently repair or delete unsupported hierarchy data. Reparenting will need separate cycle, lock and generator validation.

`.setComponentName(id:name:)` validates the complete interpreted hierarchy before changing a single name. Names follow the existing part-name rules: trim surrounding whitespace, at most 1024 UTF-8 bytes, no controls/newlines or U+FFFE/U+FFFF. Empty input removes the attribute. Component identity, ordering, children, part names, modifier fields, unknown XML and assets remain unchanged. Semantically identical input retains original bytes. Existing document/session transactions provide atomic publication and exact undo/redo.

## Scope

This stage adds no dependency, engine adapter, native menu or tree UI. It establishes the archive contract for the next M3 tree selection and inspector stage; grouping/reordering, modifier editing, effective ancestor locks and geometry differential acceptance remain open in #62. Do not use component renaming to change a legacy part name implicitly.
