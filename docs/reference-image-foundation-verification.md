# Reference-image archive foundation verification

Full `make ci` passes 177 tests, formatting, both native builds, coverage and Qt-free checks. Document coverage is 1687/1762 lines (95.74%); editor model 805/811 (99.26%); pure editor state 364/364 and undo history 97/97 (100%). Inherited C++ coverage is not measured.

Twelve new tests cover the archive boundary, editor session and pinned native engine:

- Existing `canvas.png` bytes and no-op byte identity; replacement/removal/addition and reopening.
- Exact model and unrelated binary assets; unknown root/item attributes, namespace-qualified child metadata, item ordering, payload gaps and trailing bytes.
- Zero-length asset reanchoring when its containing byte span is removed.
- Model-only net-zero transforms with a 4 MiB image retain exact original bytes; mixed model/image transactions retain both edits and exact undo. Transaction scope selects the model-only path unless a command can alter assets.
- Image-only transaction commit/undo/redo; net-zero replacement and add/remove restoring exact original archives and retaining redo; cancellation restoring the original.
- Invalid PNG signature, encoded image size, undo byte budget, reserved-name collision, item-count and header-growth limits, without partial publication.
- Editor-session image-only publication with unchanged graph and advancing document revision; rejected mixed image/node batch preserving archive and redo.
- The exact pinned engine generates the original three-node, one-part, 80-triangle capsule after adding a reference image in a transaction; Undo restores its exact original archive.

Tests were written before the missing reference-image API was implemented. Source inspection confirms Qt saves/loads `asset` `canvas.png` in `application/sources/document_saver.cc` and `document_window.cc`. Qt GUI round-trip, image decoding and canvas rendering were not performed in this foundation stage. The document layer checks encoded size/signature only; full raster validation and pixel limits must be applied by the later platform importer. No image import UI, coordinate convention change, C++ change or core pin update is included.
