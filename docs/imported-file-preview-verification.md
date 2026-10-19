# Imported file-preview verification

Tracked by #161; decision ADR 0076. Editor #160 is merged. This stage adopts
supported imported materials in the existing system providers, not full M4 parity.

Six new tests cover real imported readonly preparation, current-frame notice
selection, retained original quota cause with ordinary geometry, propagated
cancellation, invalid/cancelled render requests, actual imported alpha readback and
a real imported GLB rendered through the production encoder, and explicit rejection
of malformed textured geometry without its required UVs. All 13 focused
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
The combined editor/preview gate passed 776 tests before adding the malformed-asset
negative acceptance case. The expanded final gate now passes 777 tests; the PR-open screenshot is captured
after the committed-identity bundle rebuild. No next PR was published before #160 merged. Archive/source assets
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

## Integrated acceptance checkpoint

The editor stage #160 is merged at `cae6bd953bc51f6ed9d13711dd53970ab80e5c69`.
The combined local gate passed 776 XCTest cases before moving the preview commits
onto that squash merge. The rebase preserved the exact full source-tree identity
`fe83ef3ce2fd87d40280556fbd83a78700b389f1`; only commit ancestry changed.

An independent GLB/DS3 envelope builder removes TEXCOORD_0 from the real fixture's
textured primitive without changing its pixels or positions. The native reader
rejects this required-asset inconsistency with an invalid-document error before
publishing partial geometry, and the archive stays unchanged. This differs from
an optional image decoding/upload failure, where ordinary geometry remains usable.
No sampler or material fallback policy was changed for this acceptance test.
The final `make ci` passed 31 build-support tests and all 777 XCTest cases, all
coverage gates, formatting, Qt-free linkage and isolated app/provider rebuilds.
The final expanded focused run passed 13 tests with actual Metal access and no skips.
Exact-head automated review and every hosted CI check remain required before merge;
this does not close #143 or establish full editor parity.
