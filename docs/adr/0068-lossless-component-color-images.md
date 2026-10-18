# ADR 0068: Lossless component color-image commands

Status: accepted decision. Tracks Apple #138.

## Document commands and ownership

Add `.setComponentColorImage(id:imageID:)` for assigning a retained resource or
removing an override, and `.importComponentColorImage(id:imageID:png:)` for one
atomic import plus assignment. Expose `DocumentComponent.colorImage` as missing,
exact source reference or unsupported text. The document layer has no file picker,
ImageIO, UI, UUID generator or second native adapter.

Callers supply fresh identities. New names use `images/{identity}.png`, retaining
the inherited opaque identity shape, brace aliases and case sensitivity. New
identities cannot contain slash, period, control or invalid XML characters: those
cannot safely round-trip the reference reader's first-path-segment/filename-stem
rule. Matching existing identical bytes may be shared without rewriting their
metadata; conflicting, ambiguous or wrong-kind resources fail. A missing identity
already referenced by a component is reserved rather than implicitly repaired.
Identity interpretation compares exact UTF-8 bytes. New keys that collide under
the archive's existing name policy reject with `conflictingAsset`, including
canonically equivalent Unicode spellings, rather than overwrite another resource.

Removing or reassigning references never deletes resources. Unknown references may
live in opaque metadata and other components may share the image. Existing invalid
or unsupported source values are preserved until explicitly replaced. Reference
assignment validates identity, asset existence and kind; it does not decode pixels.

Import works entirely on immutable archive values. A failure after preparing the
asset but before completing assignment returns no new document. History marks the
command asset-changing, so clearing a newly imported reference inside a transaction
does not discard its retained asset. Comparison-only normalization of known empty
and braced/unbraced image references restores exact original bytes and redo for
net-zero retained-image transactions; saved source metadata is never normalized
by that comparison.

## Shared PNG envelope boundary

Move bounded container inspection from the Apple decoder into the existing pure
document library as `PNGContainerMetadata`. This avoids two resource/envelope
parsers; Dust3DKit already depends on Dust3DDocument, so no package or external
dependency changes. The Apple decoder retains ImageIO sample extraction, source
scanline/alpha semantics and the depth-specific transparent-gray compatibility
rule, mapping structural errors to its existing public error cases.

The shared inspector checks the selected container/IHDR rules from the
[W3C PNG specification](https://www.w3.org/TR/png-3/#11IHDR): signature, initial/unique IHDR, supported bit-depth
and color-type combinations, compression/filter/interlace fields, bounded chunk
spans, image-data presence and a complete final IEND. Import accepts at most 32 MiB
encoded input, 8192 pixels per side and 256 MiB of projected RGBA8 output. Existing
archive/item/header/model and history quotas remain independent. Inspection uses a
borrowed Data buffer synchronously and returns only immutable copied metadata.

This is structural validation, not decompression, CRC verification or full PNG
chunk-semantic validation. The subsequent platform import service must perform
actual image validation/decoding before offering user imports; the existing bake
path already does this before invoking the native baker. Retained encoded bytes
are unchanged. Logical quotas do not claim a process RSS or codec-workspace cap.
Both container and reference errors expose actionable original category/resource
information through LocalizedError.

## Verification and remaining work

Failing-first tests exposed missing command/state APIs, empty-string assignment,
Unicode-equivalent key collisions, generic diagnostics and net-zero alias/default
history behavior. Tests also cover shared resources, wrong-kind/ambiguous/missing
references, reserved missing identities, unsafe new names, input/item limits,
post-asset-preparation model-limit rejection, exact undo/save/reopen, source bytes,
opaque XML/binary assets and PNG envelope boundaries.

A real-core integration imports and assigns a fresh image, verifies the resulting
baked texture pixels and retains an old malformed but now-unreferenced asset.
Existing PNG decoder fixtures remain green after the parser extraction. Thirty
targeted tests pass. The three new pure image-state/XML/container files measure
154/154 lines and 69/69 regions covered; this is not whole-engine or native UI
coverage. Full `make ci` passes 651 tests with zero failures, formatting/build,
measured coverage thresholds, Qt-free linkage and signed bundle rebuilds. Automated
review and all remote CI checks remain required before merge.

Platform file import/decoding and native inspector/session wiring are subsequent
stages. No new UI or native interaction acceptance is claimed here. Textured
export, embedded models and full M4/editor parity remain incomplete.
