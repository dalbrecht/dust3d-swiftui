# ADR 0076: Imported materials in macOS file previews

Status: prepared locally under #161; full integrated gate, native host acceptance
and PR publication remain pending the serial delivery of #160.

## Decision

Reuse the reviewed owned imported material loader and production Metal encoder in
the existing editor-owned Quick Look/thumbnail providers. Keep one provider pair,
readonly sandbox entitlements and the viewer/QA apps without duplicate providers.
No dependencies, core pin, file format or persistence behavior change.

`FilePreviewDocument` holds matching ordinary geometry and mutually exclusive
baked/imported inputs from one immutable archive snapshot. Keep its baked accessor
and internal initializer compatible with existing callers. Supported part-linked
embedded models use authored UVs, original decoded source pixels, sampler/mip
policy, linear factors, scalar PBR, alpha and sidedness from ADR 0074. Unknown or
unsupported component-link forms still reject rather than previewing a partial
procedural model. This is not general glTF or full M4 acceptance.

The loader serializes requests and retains the 64 MiB archive limit. Existing
source-copy/encoded/decoded quotas remain independent. Cancellation propagates,
not a successful partial preview. Optional material preparation failure retains
ordinary geometry and the original error. No source file, asset, reference image
or persistent cache is written.

Quick Look adopts the matching material representation and changes its known
compatibility notice only after current GPU presentation. Existing controller
replacement/cancellation creates a separate host/view state; detached callbacks
cannot change the replacement document. Remaining component/legacy/unknown limits
stay visible. Failed upload/display returns to ordinary geometry and its cause.

The offscreen imported path uses the production encoder, a fixed fitted camera,
64 MiB logical prepared-upload quota, aligned readback and existing correct
linear-light-to-premultiplied-sRGB conversion. Dimensions remain bounded to 2048
pixels per side. Quotas exclude input/workspace, attachments/readback, driver and
in-flight overhead; they are not hard RSS/time limits.

Thumbnail policy is explicit: material **preparation** failure uses geometry and
logs its original cause privately with an operation ID. GPU/material **rendering**
failure returns the original error to the system completion handler rather than
silently claiming full material success. Successful thumbnail output does not
assert support for remaining source features.

## Acceptance

Focused tests use real imported/procedural archives, readonly byte comparison,
original quota errors, cancellation, current-frame notices and actual production
GPU readback/alpha conversion. Native Finder Quick Look and public thumbnail API
requests must be exercised using the installed existing provider identity; package
or offscreen tests alone do not prove OS hosting. Full integrated `make ci`,
exact-head automated review and every hosted check remain required before merge.
Imported atlas/baking, additional model/maps, exports and full parity remain open.
