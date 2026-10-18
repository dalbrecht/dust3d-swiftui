# Native modeling acceptance

Tracks #120. Tested October 18, 2026 against `0219ad1` using the existing
`org.dust3d.editor` application and a disposable copy named
`NativeModifiersQA-20261018.ds3`. No new application identity, human button
presses, dependency or product code change was needed for this pass.

## Known procedural controls

The fixture contains a three-node chain with two edges, exact part/component
identities, `future="retained"` on its part and an `opaque.bin` archive item with
bytes `00 ff 0a 80`. The original fixture remains unchanged. Native open, part
selection, inspector controls and the actual Metal viewport were exercised.

| Native operation | Observed result | Persistence/history evidence |
| --- | --- | --- |
| Subdivided cross-section | Checkbox on; 88 → 176 triangles | Saved `subdived="true"`; Undo/Save byte-identical to original; Redo/Save byte-identical to edited archive |
| Chamfered cross-section | Checkbox on; 176 → 352 triangles | Saved `chamfered="true"` |
| Rounded ends | Checkbox on; 352 → 416 triangles | Saved `rounded="true"` |
| Extra rings off | Checkbox off; 416 → 160 triangles | Saved `interpolated="false"` |
| Width draft and reset | 1.5 draft resets to 1.0 | No width attribute published before Apply |
| Width 3 Apply | Readable 0–2 validation notice; dismiss works | No valid edit accepted |
| Width 1.5 Apply | Inspector and rendered cross-section update | Saved `deformWidth="1.5"`; Edit-menu Undo/Save byte-identical to prior shape archive; Redo/Save byte-identical to width archive |
| Thickness 0.6 Apply | Inspector and rendered cross-section update | Saved `deformThickness="0.6"` |
| Unified deformation | Checkbox on; rendered shape updates | Saved `deformUnified="true"` |
| Hexagon preset | Menu selection updates; 160 → 240 triangles | Saved `cutFace="Hexagon"` |
| Rotation 0.25 | Clicking the field then Return applies the draft | Saved `cutRotation="0.25"` |
| Close and reopen | Fresh history; same 240-triangle mesh | All above checkbox/menu/numeric states restored in the inspector |

Archive inspection after the combined edits confirmed the unknown part attribute
and opaque asset bytes remain unchanged. The final edited archive SHA-256 is
`49d55c552126a9defa75ec30214143dbdcb9bd14108387de96523d4ba72c5390`.
A Save immediately following a preset selection hit the existing in-flight edit
guard: the native alert explained that the edit was still being applied. Dismiss
and retry after completion saved successfully. This is evidence of safe rejection,
not evidence that every possible save/edit interleaving is tested.

The full local gate on the tested product revision passed 627 tests, formatting,
build, measured coverage thresholds, Qt-free linkage and isolated signed bundle
rebuilds in PR #134. These results do not measure native interaction coverage.
A documentation delivery still requires its own gate and automated review.

## Intersections and unsupported legacy values

A separate five-node, two-part fixture (`NativeHardJoinQA-20261018.ds3`) tested
Hard joins on the incoming Crossing chain. Its checkbox changed off → on, the
actual native mesh changed 278 → 370 triangles, and only that part saved
`hard="true"`. Undo restored 278 triangles and a byte-identical original archive;
Redo restored 370 triangles and a byte-identical edited archive. Both original
part identities and the unrelated retained attribute survived.

An independent legacy fixture initially contained `future` values for subdivision,
width, unified deformation, cut-face and rotation. Its inspector displayed
explicit unsupported selections/empty drafts and the preview retained the
original `stod: no conversion` diagnostic. Open/select/Save preserved every
archive byte. Choosing subdivision On changed only `subdived`; the other four
unsupported values remained unchanged. Undo/Save restored the exact original.
Subsequent explicit replacements (width 1.25, unified Off, Triangle, rotation
0.15) recovered a 132-triangle native mesh. Unified Off uses the absent default
attribute; this is an explicit replacement, not an automatic source rewrite.
The unrelated `future="retained"` and `opaque.bin` bytes survived. The recovered
archive SHA-256 is
`2b9b68dd387b76943563f8193d9dcff60ba8b0795c4af14f8b5e096bf3728e7b`.

## Selection and linked-profile search

A two-part fixture uses the same linked-profile coordinates as the existing core
integration tests, with a separate `CutFace` part named QA Profile. Drafting width
1.7 on Long chain, selecting QA Profile, and returning restored the original 1.0
draft with Undo still disabled. Expanding Link profile showed only the other
eligible part and its exact ID. Searching `nothing matches` displayed No matching
other parts; searching `qa profile` restored QA Profile, confirming the
case-insensitive name path.

The desktop locked before the link action could be verified. That action is not
counted as performed: native linked output, profile history and profile reopen
remain pending. No human unlock/button request was made. The successful search
and draft observations are not substitutes for the unverified mutation.

## Remaining acceptance

Linked-profile selection/output, profile history/reopen, independent native
Undo/Redo for thickness/unified/profile rotation and further keyboard paths remain
in #120. Qt differential tolerances, broader topology and
modifier combinations, VoiceOver and other M3 families remain unverified. This
pass does not establish full M3 or editor parity.
