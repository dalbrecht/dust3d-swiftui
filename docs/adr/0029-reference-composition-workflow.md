# ADR 0029: Transient reference composition workflow

Status: Accepted; native Apply/save/Undo and recovery verified

## Decision

Expose Compose Reference Image in the existing reference menu. A sheet owns transient Front/Side sources, top-left pixel crops, side mirroring, source swap, image previews and an optional proposed document-origin change. Nothing writes to a document before Apply. Existing canvas.png is flattened; using it as a Front source is explicit and cannot recover original source/crop metadata. Sources/crops are not added to the archive schema.

Keep images immutable and Sendable. ReferenceCompositionService imports/decodes/composites on its actor using existing bounds and the Qt 6 default layout. A main-actor observable draft owns only presentation state and request identities, without an editor-session reference. Every source/crop change cancels the previous request; both cancellation and request identity guard publication. Stop clears state and ignores late imports/previews. Import/geometry errors preserve their typed cause and cannot become a document write.

Numeric invalid input invalidates the result and disables Apply. Explicit source/reset actions advance a source epoch so local field drafts reset even if the resulting crop equals the previous valid value. Displayed mirrored crops convert back into original source pixel coordinates before rasterization. Pointer selection uses a pure aspect-fit projection, clamping before integer conversion, and a transient GestureState rectangle. Source/crop identity checks reject stale pointer completions. Active crop tokens disable Apply until the tentative gesture finishes or cancels. Numeric controls remain the keyboard alternative; native drag-resize handles and moving an existing rectangle are not implemented by this rectangle-selection gesture.

## Atomic Apply

Capture document identity, document revision and constraint revision when the sheet opens, without retaining its archive in the target token. The session validates all three before submitting canvas.png and the optional origin command as one existing history transaction. Axis locks follow native origin policy. Selection changes are transient and do not invalidate the target. Open, edit/Undo and lock on/off cycles invalidate it. Invalid PNG/origin or stale targets fail atomically; no-ops preserve redo.

The sheet waits for the controller's publication result before dismissing. Failure leaves the draft open with the actual diagnostic. Apply disables cancellation/dismissal while the atomic operation is in progress. Cancel/disappearance cancels draft work and never writes a document. The controller completion callback runs on success, validation failure, busy/stopped rejection and cancelled operations; it does not add another archive writer.

## Presentation and acceptance

Use one identifiable sheet presentation containing its nonoptional target. A separate Boolean plus optional target produced an empty first sheet during native QA; item-based presentation removes that intermediate state. A regression covers presentation/target identity, and native QA confirmed the first presentation has content. Keep labels persistent, align each crop column, and keep content scrollable with an always-reachable action footer. Explicitly contain the scrolling content as one accessibility navigation group; this resolved the control-helper traversal failure on the QA host without hiding its controls.

The earlier native build passed imports, numeric edits, mirror/swap, physical rectangle selection and byte-identical Cancel/save. The final grouped-scroll build passed rendered inspection, Apply/save and byte-identical Undo; flattened-source recovery preserved its document and history. Held-gesture/VoiceOver and actual Qt GUI acceptance remain pending. Do not infer that acceptance from unit tests or claim Qt GUI parity. See [verification](../reference-composition-workflow-verification.md) and #56. No C++ code, core pin, dependency, lockfile or CI configuration change.


## Recovery channel (#59)

The native accessibility helper repeatedly crashed during sheet traversal while the editor remained running. Provide an explicit `--cancel-reference-composition` entry-point mode. It posts one fixed distributed-notification name scoped by the executable's bundle identity, with no user information, document paths or arbitrary command payload. Normal application arguments continue to SwiftUI. The receiver dispatches to the main actor and requests cancellation of only the most recently registered composer. That composer refuses while Apply is active; refusal never cancels another window. Normal disappearance unregisters the handler. This deliberately discards an unapplied composition draft, never the document or its undo history.

A sender prints only that it requested cancellation, not that delivery succeeded; sandboxed shells can prevent notification delivery. The native boundary needs an actual receiver/visible-window check. Pure tests cover exact command parsing, newest-only routing, busy refusal, handler replacement and idempotent unregistration. No dependency, URL scheme, document format or additional native engine entry point is introduced.
