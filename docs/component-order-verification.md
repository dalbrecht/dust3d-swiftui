# Component sibling-order verification

Regression-first tests failed for the absent command, availability and controller APIs. Four document tests cover all four moves at root/nested levels, retained descendants, opaque link/attribute/asset preservation, fixed non-component XML slots, unchanged node geometry/part flags, missing/ambiguous/unsupported targets, unsupported graph preservation, singleton and boundary no-ops, integer bounds, exact undo/redo and net-zero transactions. Session tests cover current-order availability, retained component selection, rejected-batch atomicity and redo preservation. Controller tests verify one document publication and fresh pinned-core preview for a real move, no publication/regeneration at a boundary, retained camera/selection and exact history. The disjoint two-part fixture produces the expected 32 triangles before/after ordering.

Full `make ci` passes 310 XCTest tests, strict builds, formatting, coverage gates and Qt-free linkage. Measured coverage: sibling-order resolver/XML adapter 42/44 lines (95.45%; residual defensive XML sibling-consistency rejection); component tree 61/61 and pure editor state 495/495; undo 97/97. Document overall 2038/2118; editor model overall 1297/1303; mesh 66/67. No inherited C++ or full-app coverage claim.

## Native evidence

Used the existing QA bundle and a disposable nested Capsule-derived archive. Inspected the rendered menu, tree and 80-triangle preview. At the first root position, Up/Top were disabled and Down/Bottom available. Move Down moved Assembly after the empty sibling while retaining its nested Capsule child and selected identity. At the last position, Down/Bottom became disabled and Up/Top available.

Native Save wrote the new root order. Independent XML inspection verified both root names/order, the nested child name, three nodes and both edges. Undo followed by settled Save restored the original archive byte for byte; Redo/Save matched the applied archive byte for byte. The preview remained available. A final Undo/Save restored the disposable fixture exactly, without discarding data or killing the app.

The computer-control helper timed out during an attempted Dock activation after the chooser remained inactive. Re-polling the same live editor handle recovered observation and showed usable Open controls; native acceptance then completed in the same process. This was not treated as a terminal app failure or grounds to restart/discard a document. No reference design exists, so no pixel baseline was invented.

Inherited source inspection confirms Up/Down/Top/Bottom ordering and the absence of part-state lock checks on those ordering actions. Full Qt numerical/GUI differential acceptance for order-sensitive modifier combinations, physical drag-reordering, deep/minimum-size and VoiceOver checks remain pending. This stage does not add grouping or reparenting or complete M3. See [ADR 0033](adr/0033-component-sibling-order.md) and #62.
