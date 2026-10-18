# ADR 0066: Rendered macOS file previews

Status: implemented locally for Apple #132; automated PR review pending.
Native Finder Quick Look displays the colored Sword object and toggles wireframe.
Public QLThumbnailGenerator requests return rendered Capsule and Sword thumbnails
(type thumbnail, 512×512) from the installed sandboxed provider.

## Decision

Provide both a `QLThumbnailProvider` thumbnail extension and an
`NSViewController` conforming to `QLPreviewingController` for read-only Quick Look.
Use the editor as the owning application bundle for both extensions, with stable
identifiers under `org.dust3d.editor`. The separately installed viewer continues
to recognize the same document type without shipping duplicate providers. This
keeps system document integration with the primary authoring app and avoids
competing extension copies when both native apps coexist.

Shared source and dependencies remain in SwiftPM. Installed Xcode templates
confirm extension-point metadata, supported content types, principal classes,
sandbox and user-selected readonly entitlements. SDK-only probes compile actual
extension executables through both SwiftPM backends using Foundation's
`_NSExtensionMain` entry. The native backend additionally needs a linker alias
from that symbol to its synthesized `<Target>_main` name. No dummy or unreachable
main implementation is needed. Packaging embeds both executables and shader resources with verified readonly
sandbox entitlements. Native OS hosting is verified separately from compilation.

The thumbnail completion callback has a legacy non-Sendable SDK signature. The
SDK explicitly permits asynchronous invocation after the override returns.
A `sending @escaping` override parameter permits checked transfer into the
rendering task under Swift 6; both backend probes compile without custom
unchecked Sendable or preconcurrency suppression. Copy request URL, sizes and
scale before crossing isolation. The SDK request exposes no cancellation flag;
do not invent a host cancellation API. Enforce cooperative task/lifetime bounds
where available and disclose non-preemptible native phases.

## Data and rendering boundaries

`FilePreviewDocumentService` serializes read-only work, reads one archive snapshot
(up to 64 MiB), validates metadata through the existing document module, and
prepares ordinary geometry plus optional matching material output. The rendering
target directly depends on the existing `Dust3DDocument` target for this boundary;
no external dependency is added. Material failures retain their original cause
and ordinary geometry. Empty documents are explicit; embedded/unsupported links
reject instead of silently producing a partial procedural object.

Baking uses bounded preview maps and separate encoded/decoded/UV/output quotas.
Input bytes, unknown archive items and original image resolution stay unchanged.
`canvas.png` is a reference image, never an object thumbnail. Existing files must
preview on demand without being re-saved. No network or persistent writes occur
in the shared preview loader/renderer.

`FilePreviewRenderer` uses the production material encoder with a deterministic
fitted camera and transparent background. GPU setup/upload stays on its builder
actor; rendering owns GPU objects on the main actor. Readback uses aligned rows,
waits for GPU completion before releasing resources, and transfers copied Data
for background repacking/color conversion. Image dimensions are bounded to 2048
pixels per side and replies fit within requested point bounds, including
fractional sizes. Logical quotas exclude workspace, driver overhead and other
in-flight allocations; no hard RSS claim is made.

Metal blends in linear light before sRGB attachment encoding. Core Graphics
expects encoded channels premultiplied by alpha. Transparent readback therefore
unassociates in linear light, encodes, then reassociates in encoded space; treating
the raw attachment bytes as ordinary premultiplied sRGB would create edge halos.
Opaque samples stay unchanged, zero-alpha RGB becomes zero, and source padding
is stripped. Tests cover this independently of the material shader.

## Verification and limits

The full local gate passes 627 tests with zero failures, including production GPU
readback, alpha conversion, invalid dimensions, background drawing callbacks,
read-only loading, unsupported links and archive quotas. Rebuild checks package
both providers twice and verify signatures/resources; native targets are Qt-free.
Native Quick Look rendered Sword from its existing archive and wireframe toggled.
Finder icon and gallery views display the rendered object. A 2× callback test
requires every bitmap pixel to be filled, preventing undersized corner thumbnails.
Public macOS thumbnail requests returned rendered Capsule and Sword images.

Quick Look drawing callbacks execute outside the main actor. Construct the
Sendable drawing callback in the nonisolated image factory; constructing it in the
render task inherits actor isolation and crashes under the real OS host. A
background drawing regression test covers this boundary.

Rebuilding a host bundle replaces its registered extension identity. Re-register
or launch the rebuilt editor before native acceptance; temporary bundle rebuild
checks remove their own bundles and must not be mistaken for installed providers.
Distribution signing/notarization remains outside this prototype. Embedded GLB
links are explicitly unsupported rather than silently omitted. Atlas-wide alpha
classification and the shared renderer's existing material limitations remain.
These previews do not establish full M4 parity or inherited-core coverage.
