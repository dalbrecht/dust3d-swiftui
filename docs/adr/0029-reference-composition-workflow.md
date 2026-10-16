# ADR 0029: Transient reference composition workflow

Status: Accepted; final-build native acceptance pending

## Decision

Expose Compose Reference Image in the existing reference menu. A sheet owns transient Front/Side sources, top-left pixel crops, side mirroring, source swap, image previews and an optional proposed document-origin change. Nothing writes to a document before Apply. Existing canvas.png is flattened; using it as a Front source is explicit and cannot recover original source/crop metadata. Sources/crops are not added to the archive schema.

Keep images immutable and Sendable. ReferenceCompositionService imports/decodes/composites on its actor using existing bounds and the Qt 6 default layout. A main-actor observable draft owns only presentation state and request identities, without an editor-session reference. Every source/crop change cancels the previous request; both cancellation and request identity guard publication. Stop clears state and ignores late imports/previews. Import/geometry errors preserve their typed cause and cannot become a document write.

Numeric invalid input invalidates the result and disables Apply. Explicit source/reset actions advance a source epoch so local field drafts reset even if the resulting crop equals the previous valid value. Displayed mirrored crops convert back into original source pixel coordinates before rasterization. Pointer selection uses a pure aspect-fit projection, clamping before integer conversion, and a transient GestureState rectangle. Source/crop identity checks reject stale pointer completions. Active crop tokens disable Apply until the tentative gesture finishes or cancels. Numeric controls remain the keyboard alternative; native drag-resize handles and moving an existing rectangle are not implemented by this rectangle-selection gesture.

## Atomic Apply

Capture document identity, document revision and constraint revision when the sheet opens, without retaining its archive in the target token. The session validates all three before submitting canvas.png and the optional origin command as one existing history transaction. Axis locks follow native origin policy. Selection changes are transient and do not invalidate the target. Open, edit/Undo and lock on/off cycles invalidate it. Invalid PNG/origin or stale targets fail atomically; no-ops preserve redo.

The sheet waits for the controller's publication result before dismissing. Failure leaves the draft open with the actual diagnostic. Apply disables cancellation/dismissal while the atomic operation is in progress. Cancel/disappearance cancels draft work and never writes a document. The controller completion callback runs on success, validation failure, busy/stopped rejection and cancelled operations; it does not add another archive writer.

## Presentation and acceptance

Use one identifiable sheet presentation containing its nonoptional target. A separate Boolean plus optional target produced an empty first sheet during native QA; item-based presentation removes that intermediate state. A regression covers presentation/target identity, and native QA confirmed the first presentation has content. Keep labels persistent and content scrollable with an always-reachable action footer.

The earlier native build passed imports, numeric edits, mirror/swap, physical rectangle selection and byte-identical Cancel/save. The final label/scroll/active-gesture build still needs native Apply/Undo and rendered inspection because the app-control connection closed. Do not infer that acceptance from unit tests or claim Qt GUI parity. See [verification](../reference-composition-workflow-verification.md) and #56. No C++ code, core pin, dependency, lockfile or CI configuration change.
