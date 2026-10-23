# Controlled native modifier acceptance

Tracks #120 and the M3 acceptance in [the editor plan](editor-port-plan.md).
This records specific native cases, not complete modeling or editor parity.
The October 18 exploratory observations retain their provenance limits in
[native-modifier-acceptance.md](native-modifier-acceptance.md).

## Runtime identity

All passes reused `org.dust3d.editor.combine-qa` at
`/private/tmp/dust3d-validator-safe-build/app-qa/Dust3DEditor.app`. No bundle was
rebuilt while its process was being tested, no new app ID was introduced, and
all files were disposable QA copies. Repository fixtures were untouched.

| Pass | Loaded clean source | PID | Core pin |
| --- | --- | ---: | --- |
| Earlier controlled shape/width/profile cases | `ac6da0214bbdc36281076411db401c05e635d0c9` | 79169 | `41af7d4c1b67dd037e02858e3ef0fdb96a84aebb` |
| Thickness/unified and intersecting hard-join history/reopen, October 23 | `2011b362df1495862eb8ee10c41ef5ccb7ba9718` | 77988 | Same pin |

The earlier immutable identity and binary hash are retained in
`pr244-native-runtime.json`. During the later pass, About diagnostics were read
again from the existing process, confirming clean source, the above revision,
source digest
`b9dfc3de67e2d474c626d11c4cfc265725e8bc10e81c99087bf9d0607bc7d65f`,
and immutable capture time `2026-10-23T21:17:31Z`. Process inspection confirmed
the owned executable path. The current documentation branch has no implementation
difference from `2011b362` in Sources, Tests, Package.swift or scripts; that does
not change the revision attributed to the loaded process.

## Earlier controlled cases

These cases are transcribed from the retained October 23 controlled checkpoint,
not inferred from the October 18 process whose loaded revision was unverified.
The disposable Capsule copy began with three nodes and 80 triangles.

| Native operation | Visible result | Stored/history evidence |
| --- | --- | --- |
| Chamfer on | 80 → 160 triangles | Only `chamfered=true`; Undo/Save exact original, Redo/Save exact edited archive |
| Width 1.5 Apply | Width field and preview update | Only `deformWidth=1.5`; exact prior/edited archives through Undo/Redo/Save |
| Close/reopen | Chamfer on, width 1.5, 160 triangles | Fresh disabled Undo/Redo |
| Hexagon preset | 160 → 240 triangles | Only `cutFace=Hexagon`; exact history saves |
| Rotation 0.25 | Rotation field restored after history | Only `cutRotation=0.25`; exact history saves |
| Subdivision off | 240 → 120 triangles | Absent false-default attribute; exact history saves |
| Rounded ends off | 120 → 72 triangles | Absent false-default attribute; exact history saves |
| Extra rings off | 72 → 72 triangles | `interpolated=false`; exact history saves |
| Width 3 Apply | Bounded 0–2 validation notice | Dismiss and Reset work; archive unchanged, width restored to 1.5 |

An initial external assertion incorrectly expected explicit `false` for every
false default. Inspection of PartModifiers.swift and the archives established the
existing absent-default behavior; this was a QA assertion correction, not a product
fix. These are cumulative simple-chain cases, not all modifier combinations.

## Thickness and unified deformation

The later pass used a fresh copy named `NativeDeformationQA-20261023.ds3` of the
saved controlled fixture. Starting state: three nodes, 72 triangles, chamfer on,
width 1.5, thickness 1.0, Hexagon, rotation 0.25 and Unified off. Its archive had one
model item; unknown/binary-asset retention is not established by this fixture.

1. Click Thickness scale, enter `0.6`, inspect the draft and disabled Undo. Saved
   bytes remain exact baseline before applying. Return applies the draft; settled
   native Save changes only `deformThickness=0.6` in the model tree.
2. Command-Z, wait for thickness 1.0/Redo enabled, then Save: byte-exact original
   archive. Command-Shift-Z, wait for thickness 0.6, then Save: byte-exact edited
   archive. One immediate Undo/Save hit the existing in-flight edit guard. Its
   readable alert was dismissed; saving after completion succeeded. This is safe
   rejection evidence, not proof of every save/edit interleaving.
3. Click Unified deformation. Save changes only `deformUnified=true` relative to
   the thickness archive. Undo/Save restores the thickness archive byte for byte;
   Redo/Save restores the unified archive byte for byte.
4. Close the saved document normally and reopen through the native Open panel.
   Select the part: thickness 0.6, Unified on, width 1.5, Hexagon and rotation 0.25
   return, with 72 triangles and fresh disabled Undo/Redo. Saved bytes remain exact.

The actual Metal preview and both deformation controls were inspected. An
unchanged triangle count does not establish numerical deformation/Qt parity.
The other owned `NativeCreatedChainQA.ds3` window retained Node 2 selection, empty
history and its exact prior archive. Original QA input and global SVG bytes/mtime
were unchanged. No process was killed or document discarded.

| Snapshot | SHA-256 |
| --- | --- |
| Baseline | `56c71b74defe7477d9633c9704417b88185c76818a96322590608cb307004f02` |
| Thickness 0.6 | `8dddeb110e1a4080e8335cd6c34860bfeff03cd8951d15f122e9b2fefaa2ec59` |
| Unified on | `2ee330aa78210db298235c393a610c24e353590de2a648ee6ded3d30cf934ac9` |

Independent bounded archive/XML inspection compared every model node/attribute
and item, allowing only the named part attribute per edit. Runtime JSON, exact
archives, semantic-check scripts and native PNGs are retained in the recovery
checkpoint `2026-10-23-numeric-admission`. These are diagnostic artifacts, not
committed pixel baselines. Screenshots include `native-thickness-applied.png`,
`native-unified-applied.png` and `native-deformation-reopened.png`.

## Intersecting hard joins

The same loaded `2011b362` process opened `NativeHardJoinQA-20261023.ds3`,
a disposable five-node/two-part fixture matching the existing ordinary
`testHardJoinChangesTheActualIntersectingPartSeam` integration geometry. A pure
Dust3DDocument utility created the archive and expected edit without invoking the
engine. Both parts contain unknown `future="retained"` metadata, and the archive
includes `opaque.bin` with bytes `00 ff 0a 80`.

1. The initial native preview has 278 triangles. Select Crossing and enable Hard
   joins: the checkbox turns on and the preview changes to 370 triangles.
2. Native Save matches the pure expected archive byte for byte. Independent
   bounded archive/XML inspection permits only Crossing's `hard="true"` addition;
   all item metadata, other attributes and opaque payload bytes are retained.
3. Undo, wait for Hard joins off and 278 triangles, then Save: exact baseline.
   Redo, wait for Hard joins on and 370 triangles, then Save: exact edited archive.
4. Close the saved document normally and reopen it through the native Open panel.
   Crossing restores Hard joins on and 370 triangles, with fresh disabled Undo
   and Redo. The saved archive still matches the pure expected result exactly.

Baseline SHA-256 is
`a9823136a923d817f376e56f52f782ce66ff82a0c3271058ede9af774178af12`;
the hard-join archive is
`4b61b0ecba8ed5f4c61e06fa60ad6ac775cdc94f42d02ac214514a8bb1515146`.
Both other owned QA documents retain their prior exact bytes. Generator source,
archives and `native-hardjoin-before.png`, `native-hardjoin-applied.png` and
`native-hardjoin-reopened.png` are retained in the recovery checkpoint. This
establishes this intersecting case, not every seam configuration or Qt parity.

## Linked profile replacing unsupported metadata

The same loaded clean `2011b362` process opened a disposable five-node fixture
matching `PartCutFaceStoreTests` geometry: a three-node owner and a separate
two-node CutFace part. The owner starts with unsupported `cutFace="future"`.
Both parts retain unknown metadata and an opaque binary asset. The pure document
utility generated the baseline and expected linked archive without engine calls.

Select Owner, expand Link profile and choose Profile by its displayed exact ID
`{bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb}`. The preset display changes from
Unsupported source value to Linked profile. Native Save matches the pure expected
archive byte for byte. Undo restores Unsupported source value and Save matches
the original archive exactly; Redo and Save restore the exact linked archive.
Closing normally and reopening restores Linked profile with fresh disabled
Undo/Redo. The final saved bytes still match the pure expected edit, SHA-256
`b103a3b0612cc994032c9e85759935931306bd4f62475ab8e4056606feed7a2f`.

Both visible previews contain 88 triangles. This proves native selection,
replacement, history and persistence for this case; triangle counts alone do not
prove the geometric difference or Qt parity. Broader source-profile node mutation,
missing/cyclic link interactions and other legacy replacements remain open.
Generator source, archives and `native-linked-profile-reopened.png` are retained
in the recovery checkpoint, outside committed pixel baselines.

## Remaining acceptance

Source-profile mutation and broader linked-profile interactions,
other unsupported legacy replacements, other modifier families, full Qt differential
checks, VoiceOver, supported-OS coverage and broad gesture acceptance remain open.
This pass did not exercise GLB, the quarantined writer fixture, allocation failure,
resource exhaustion, active signal delivery, animation or rig-pose paths. Pins
and quarantines remain unchanged.

CUA paste did not alter the Open panel's Go to Folder field; an accessibility value
setter resolved the verified path and reopening succeeded. The cause is not
isolated to product code versus the control helper. Keyboard paste into native
file panels is not counted as passed, and no speculative product fix is claimed.
