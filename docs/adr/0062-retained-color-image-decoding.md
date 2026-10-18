# ADR 0062: Retained color-image decoding

Status: full local gate passes; automated review and remote CI pending. Apple #125.

## Boundary and dependency direction

The lossless document library resolves component colorImageId values to retained
archive metadata. It returns canonical engine identities, actual asset names and
encoded byte counts, without decoding or copying payload bytes. Match the preserved
reference reader's image-name stem handling and native opaque identity rules,
including brace aliases, case sensitivity and valid all-zero IDs. Reference metadata
compares image identities/archive keys by exact UTF-8 bytes, preserving distinct
canonical-equivalent Unicode spellings. Missing,
ambiguous and wrong-kind referenced resources fail explicitly. Unrelated opaque
assets remain unchanged. Archive keys are never extracted as filesystem paths.

Dust3DKit now depends on the existing pure Dust3DDocument library. The shared
ArchiveTextureBakingService actor composes its bounded archive/XML parser, Apple
PNG decoding and the owned native baking SDK. Dependency direction stays inward:
Apple infrastructure uses the document domain. No additional external dependency
or second archive/native adapter is introduced. Caller-side composition was
rejected because viewer/editor implementations would duplicate resource policy.
A separate asset target would add package structure without a distinct consumer
or reusable boundary at this stage.

## Pixel contract and resource policy

MeshPNGDecoder uses system ImageIO/CoreGraphics sample providers without thumbnail
transforms, CGContext rendering, color conversion or premultiplication. It copies
source scanline order to tightly packed straight RGBA8. Grayscale expands to RGB;
indexed palettes resolve to RGB; transparency remains unassociated. Match the
reference PNG loader's zeroed RGB for keyed transparent 2/4/8-bit grayscale;
1/16-bit keys and explicit alpha preserve hidden samples. Twenty-one fixtures
were compared with Qt 6.12 QImage RGBA8888, including this depth-specific policy.
Sixteen-bit
samples round using the reference QRgba64 div_257 rule. EXIF orientation does not
rotate UV color charts. The existing reference-image thumbnail path is separate
because it transforms/premultiplies presentation images.

Check encoded bytes, IHDR dimensions (1...8192), bounded chunk spans and complete
IEND before ImageIO; check final RGBA bytes before image/output allocation.
Default limits are 32 MiB per encoded image, 128 MiB total encoded referenced
images, and 256 MiB total decoded RGBA inputs. Configurable quotas must be positive
and at most 256 MiB. Distinct referenced images count once after alias resolution.
All encoded totals are checked against metadata before asset payload copies.
Each image receives the remaining aggregate decoded quota before decoding.

These are logical payload quotas, not a hard process RSS limit: the retained
archive, ImageIO samples/workspace, native baking workspace and copied output are
additional allocations. Cancellation checks surround image decoding, occur at
RGBA row boundaries, and propagate to the existing native cancellation token.
Synchronous ImageIO and inherited native algorithms are not forcibly preempted.
Decode failures retain the specific asset name and original typed decoder cause;
document/native errors propagate without generic replacement.

## Evidence and remaining work

Failing-first tests established the missing document, decoder and service APIs.
Independent PNG fixtures cover RGB/grayscale/indexed/alpha, 1/2/4/8/16-bit samples,
transparency keys, low alpha, hidden RGB and encoded orientation. Integration uses
the actual pinned native baker, verifies expected RGBA output, byte-preserved
archive/opaque assets, exact aggregate budgets and cancellation-before-load.
See [verification](../archive-texture-decoding-verification.md) for gate results.

App preview/rendering remains unchanged. Editor bake scheduling/invalidation,
seam-aware indexing, PBR/transparency/AO, textured exports and full M3/M4/editor
acceptance remain subsequent reviewed work. The current tests establish sample
contracts, not a complete Qt color-management/rendering parity result.
