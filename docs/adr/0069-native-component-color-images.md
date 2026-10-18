# ADR 0069: Native component color-image workflow

Status: implemented and locally verified for Apple #140; PR review/remote CI pending.

## Decision

Connect the lossless commands from ADR 0068 to the component inspector through
`EditorSession`, captured `ComponentColorImageTarget` values and an injectable
background `ColorImageService`. Import creates a fresh safe image identity and
assigns it in one undo step. Retained-image assignment and clearing are independent
undo steps; clearing never deletes resources. Unreferenced images remain available.
No new package or C++ adapter is introduced; the reviewed core pin is unchanged.

The inventory preserves source order and byte identities. Brace aliases group as
the reference reader does; case and Unicode-distinct encoded identities do not
collapse through Swift String equality. Ambiguous, wrong-kind and unsupported
resources are visible but cannot be chosen. Metadata eligibility never asserts
pixel validity. Selected retained payloads are copied and decoded on the service
actor, not on the UI actor. Snapshot construction inventories metadata on the
editor actor. Bounded pure presentation functions describe missing/unsupported
references without rewriting them or assuming parent inheritance behavior.

## Raster boundary

Accept regular local PNG/JPEG/BMP/GIF/TIFF files through security-scoped,
cancellation-aware reads in at most 64 KiB chunks. Bound input and output to
32 MiB, dimensions to 8192 per side, logical RGBA output to 256 MiB, and decoded
non-PNG row storage to 256 MiB. Read one extra byte to detect growth after the
metadata check. ImageIO, conversion and driver workspaces are outside these
logical quotas; no total RSS cap or preemption of synchronous decoder calls is
claimed. Cancellation is checked before/after native decoding and encoding.

Valid PNG imports keep original bytes after full `MeshPNGDecoder` sample decoding.
The document's PNG envelope parser alone is insufficient validation. Other formats
use ImageIO's first encoded frame, without EXIF display-orientation transforms,
then encode and fully validate PNG. This matches the existing material decoder's
encoded-scanline contract; it deliberately does not reuse the reference-canvas
thumbnail path, which bakes display orientation. Additional GIF/TIFF frames are
not imported. Non-PNG conversion can lose format-specific metadata/precision.
ImageIO determines non-PNG RGB sample conversion; generated PNG profiles may be
retained, but baking reads encoded unassociated samples without a profile
conversion. Exhaustive Qt JPEG/CMYK/profile/orientation parity is unverified.
The pinned Qt component importer uses `QImage::load`; no claim of identical
cross-platform codec results follows from that reference path.

Read and preparation errors retain both the source filename/resource name and
original typed cause. Cancellation remains `CancellationError`. Invalid pixels
never reach an editing command. The session revalidates the captured document,
revision and singleton component before an atomic command publishes.

## Lifecycle and UI

Preparation has its own cancellable request and does not block ordinary editing
or saving. Any subsequent editing/selection operation, new import, document load
or stop invalidates it. A delayed service that ignores cancellation cannot publish
assets or errors after invalidation. A visible Cancel button and Escape cancel
preparation; native file pickers have their own Cancel action. The file picker
captures its component target before opening, and component replacement dismisses
its local presentation. Import/assignment/clear refresh material output without
regenerating geometry; undo/redo retain the established general regeneration path.

Store operations also carry a publication epoch across replacement/stop, so an
obsolete asynchronous callback cannot replace newer snapshots, reset their busy
state or surface a late error. The session checks cancellation before publishing
its state. Current source identities/revisions still govern baked result acceptance.

Use native system buttons, semantic colors, existing inspector typography and
persistent accessible labels. Retained rows are lazy and height-bounded; untrusted
text is bounded before layout. Selectable source text has explicit byte identity
so AppKit recreates its accessibility value when the source changes.

## Verification and limits

See [native workflow verification](../native-component-color-images-verification.md).
This stage does not complete M4, textured export, embedded models or #120's broader
modeling acceptance. Distribution signing/notarization remains separate.
