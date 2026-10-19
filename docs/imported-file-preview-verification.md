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
must rebuild/reuse these identities rather than add competing providers. The rebuilt registered provider pair returned an actual 512×512 thumbnail via
public QLThumbnailGenerator (thumbnail representation, 8600 PNG bytes), saved at
`/private/tmp/dust3d-imported-system-thumbnail.png`. The result was visually
inspected and contains the masked imported material, not an icon/reference image.
Finder icon view displayed the rendered object. Finder Quick Look opened the
unchanged disposable archive, displayed the imported material without its applied
limitation, toggled wireframe, orbited and fitted successfully. A transient Finder
filename-edit state was cancelled before Quick Look; independent byte comparison
confirmed the disposable archive and source fixture remain unchanged. The rebuilt
providers retained their original identifiers and installed path. Native GUI
checks used computer-use tools; thumbnail generation used the public SDK.

These results use local preparation commit `cd303fb` from merged viewer master.
The complete local gate on this viewer-based preparation passes: 31 build-support
tests, 772 XCTest cases, coverage gates, formatting, Qt-free linkage and isolated
app/provider rebuild checks. Focused FilePreviewDocumentService coverage is
116/124 lines (93.55%), FilePreviewRenderer 121/128 (94.53%) and FilePreviewView
130/196 (66.33%). These thin OS/GPU/UI boundaries are reported separately from
pure-library gates; native hosting is not represented as instrumented unit coverage.
Metal tests may skip without an available device; the recorded 92 rendering tests
and focused 12-test GPU run had no skips.
Integration with #160, the complete gate on that integrated head and the PR-open
screenshot remain pending. No next PR is published
before #160 merges. Archive/source assets
must remain byte-exact; no whole-engine coverage or full M4 parity is claimed.

## Interface review (full mode, system preview adoption)

Existing SwiftUI/AppKit controls, semantic system colors and SF Symbols remain.
No new style system, motion or screenshot baseline was introduced.

| Category | Evidence | Result |
| --- | --- | --- |
| Typography | Actual Quick Look summary, native labels and existing layout tests | Existing hierarchy retained; no new decorative text |
| Surfaces | Native Finder icon, transparent system thumbnail and Quick Look content | Rendered object replaces geometry-only material fallback for supported sources |
| Icons | Quick Look Wireframe/Fit and system window controls | Existing system controls retained; no duplicate provider or icon system |
| Animations | No new transitions; native opening transition inspected before content | Readiness judged after content loads, not its opening transition |
| Performance | Actor preparation/upload, bounded readback and actual public SDK request | Native thumbnail returned without opening an app window; hard time/RSS budgets remain M8 |

| Severity | Before | After | Why |
| --- | --- | --- | --- |
| MEDIUM | Imported models lost material/sampler/mask appearance in file previews | Supported source facts use the reviewed renderer in both providers | A preview should represent the object in the archive |
| MEDIUM | Thumbnail preparation failure could lose its diagnostic at presentation | Ordinary fallback retains the cause and logs it privately with operation context | Derived output failure must stay diagnosable |

Rejected: a custom Quick Look theme would conflict with system chrome; animated
mesh entrances would repeat on preview changes; removing all compatibility notices
would conceal unsupported source features. Verdict: **Approve for this local
preview stage**, subject to integrated-head gate, exact-head review and all hosted
checks before publication/merge. Full M4 and production parity remain open.
