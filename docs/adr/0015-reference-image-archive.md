# ADR 0015: Undoable Qt-compatible reference image assets

Accepted 2026-10-15. Reference-image archive foundation for M2, tracked in #31.

Qt saves its turnaround PNG as an archive item of type `asset` named `canvas.png` (`application/sources/document_saver.cc`) and loads that exact slot (`document_window.cc`). Preserve that representation. Expose opaque existing bytes through `referenceImagePNG`; add `.setReferenceImagePNG(Data?)` to replace/remove the slot using normal immutable document commands and undo history. Reject a reserved-name collision with another item type rather than overwriting unrelated content.

The document layer enforces a PNG signature, a 32 MiB encoded-image cap and existing archive/header/item bounds. Full raster decoding, supported input formats, pixel/decompression limits, conversion to PNG and user-facing import diagnostics belong at the platform import boundary. Opening/reading an existing document does not decode or rewrite its image bytes. Signature validation alone is not a claim that an image is decodable or safe to render.

Generalize the existing model payload replacement to a private item replacement/removal primitive. Preserve raw unrelated model/asset data, payload gaps, trailing bytes, item ordering and unknown header fields/namespaces. Keep target metadata on replacement; removal intentionally removes that target entry. Adjust offsets and reanchor zero-length entries when their byte range is removed. New images append after existing payload without rebuilding unrelated items. Equal image replacement and absent-image removal return the original value byte-for-byte.

Transactions can now change assets without changing model XML. Net-zero detection therefore compares canonical model data plus header metadata and every non-model item’s exact bytes. Normalize only known model serialization and archive offset/size fields; restore the original archive for truly net-zero transactions. Asset changes, unknown metadata differences and added/removed items must not be discarded as no-ops. History size limits remain authoritative and rejected commands/batches preserve redo.

This stage adds no image import UI or renderer, and does not change canvas orientation. Qt's image coordinates use image-height-normalized X/Z and screen-down Y; native alignment needs an explicit follow-up. No core dependency or C++ change is required. Archive/actor tests and a pinned-engine geometry compatibility test validate this boundary; Qt GUI and raster rendering acceptance remain separate.
