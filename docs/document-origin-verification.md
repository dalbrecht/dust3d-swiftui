# Document origin foundation verification

Full `make ci` passes 214 tests, formatting, warnings-as-errors builds, coverage and Qt-free linkage checks. Document coverage is 1849/1924 (96.10%), editor model 849/855 (99.30%), pure editor state 391/391 and undo 97/97 (100%). This report does not measure inherited C++ coverage or native origin UI.

Six new document tests cover complete origins, exponent/alternate numeric spellings, zero/negative/boundary coordinates, exact no-op bytes, missing/partial/nonnumeric/nonfinite/oversized existing fields, explicit repair without asset loss, invalid proposed coordinates on every axis, unknown XML preservation, graph independence, exact undo/redo and net-zero transactions preserving original spelling and redo. Tests first failed against the absent API. Net-zero coverage then caught attribute reordering; updating attributes in place fixed that failure.

A pinned-core integration test shifts the capsule origin by (+0.25,+0.125,-0.5) and verifies that both minimum and maximum mesh bounds shift by (-0.25,+0.125,-0.5), within 0.00001. Triangle/node/part counts and all saved node values remain unchanged. This checks the inherited Y/Z sign convention without comparing vertex order or changing expected geometry automatically.

No origin UI, Qt auto-settlement parity, global alignment, mirror-specific corpus or Qt GUI differential result is claimed. Unsupported original origins are reported unavailable by the reader and preserved on open/save; only explicit valid edits replace them. See [the decision](adr/0019-document-origin.md).

Automated review identified graph validation leaking into origin-only mutation. A legacy fixture with a valid numeric node referencing a missing part first failed the origin edit with `invalidNode`. The origin command now returns after bounded model replacement, independently of editor graph validation; the regression verifies unchanged unsupported graph metadata/assets and exact Undo/Redo. Full `make ci` passes again.
