# Part shape modifier verification

Tracks #62. Decision: [ADR 0040](adr/0040-part-shape-modifiers.md).

## Automated contracts

Document tests cover defaults and exact inherited boolean spellings for all five
flags, unsupported metadata preservation, empty interpolation ambiguity, explicit
replacement, exact undo/redo, semantic no-op bytes and redo preservation,
missing/ambiguous part rejection, unknown attributes, assets, graph and unrelated
part flags. Explicit metadata edits preserve visibility/lock/disable settings.

Controller tests use actual core-generated geometry. Each flag publishes one
change, retains part selection and camera, regenerates, ignores a semantic no-op,
and restores exact archive bytes and meshes with undo/redo. Four shape flags alter
a single three-node chain; all sixteen combinations generate nonempty finite
meshes with unit normals. A separate oblique two-part crossing exercises a real
hard-join seam difference; hard joins need intersecting parts to affect output.

The initial full local gate passed 359 tests against the previous engine pin.
The isolated foundation full gate then passed 360 tests against exact core
`382fe0be977170812577ab400873c10fc6f575e5`, including the rounded-crossing
regression added by the dependency PR. Formatting, native builds, Qt-free linkage,
coverage and signed bundle-rebuild checks pass. Measured line coverage: document
2351/2434, editor model 1394/1400, pure editor state 523/523, undo domain 97/97,
orbit camera 33/33 and mesh library 66/67. These do not measure native UI/Metal or
the inherited C++ engine.

## Native inspector follow-up and acceptance pending

This stage delivers the document/controller foundation. The inspector is a
separate follow-up because the QA desktop is unavailable and the user cannot
perform manual interactions. No native controls or rendered/native interaction
acceptance are claimed for the foundation PR. Reuse
`/private/tmp/dust3d-combine-qa/Dust3DEditor.app` and bundle identity
`org.dust3d.editor.combine-qa` when the desktop is available; do not create a fresh
app identity. Prepared independent fixtures are `PartModifiersQA-20261016.ds3`
and `PartHardJoinQA-20261016.ds3` in the temporary QA directory.

Check all five control labels/defaults, explicit replacement of an unsupported
value, successful rendering and selection retention. Save, Undo/Save and
Redo/Save must preserve unknown metadata/assets and reproduce exact original and
edited archives. Select the second incoming part for the hard-join fixture.
Inspect the rendered inspector, keyboard interaction and readable explanatory
text. Broader Qt differential checks, interacting modifier families and VoiceOver
remain M3 acceptance work; full modifier parity is not claimed.

The native inspector stage now has [offscreen rendering and acceptance evidence](native-part-modifiers-verification.md)
for known/unsupported flags in both appearances, with actual native interaction
still pending. The foundation's historical test counts above remain its original
verification record; the native stage reruns the full current gate.
