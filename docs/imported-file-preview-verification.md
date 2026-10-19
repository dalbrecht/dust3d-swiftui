# Imported file-preview verification

Tracked by #161; decision ADR 0076. Local preparation only: #160's hosted gate and
merge precede publication of this stage.

Five new tests cover real imported readonly preparation, current-frame notice
selection, retained original quota cause with ordinary geometry, propagated
cancellation, invalid/cancelled render requests, actual imported alpha readback and
a real imported GLB rendered through the production encoder. All 12 focused
imported/existing file-preview tests pass with actual Metal access and no skips.
The initial sandboxed run skipped three GPU cases because the device was hidden;
it is not used as GPU acceptance evidence.

The existing registered providers are in
`/private/tmp/dust3d-editor-screenshot/Dust3DEditor.app`, with identifiers
`org.dust3d.editor.quicklook` and `org.dust3d.editor.thumbnail`. Native acceptance
must rebuild/reuse these identities rather than add competing providers. Actual
Finder Quick Look/thumbnail hosting, full integrated gate, measured coverage,
interface review and publication screenshot remain pending. Archive/source assets
must remain byte-exact; no whole-engine coverage or full M4 parity is claimed.
