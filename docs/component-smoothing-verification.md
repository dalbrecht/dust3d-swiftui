# Component smoothing cutoff verification

Tracks #62. Decision: [ADR 0039](adr/0039-component-smoothing-cutoff.md).

## Automated evidence

Document contract tests first failed for the absent smoothing metadata/command;
controller tests first failed for the absent action. Six new tests cover missing,
empty, valid numeric spellings and unsupported source values; finite 0–180 bounds;
missing/ambiguous identities; XML/comments/attributes/assets and reopen; semantic
no-op bytes and redo; exact history; atomic failed batches and stable selection
and interaction locks. Invalid controller input surfaces a typed range diagnostic
without publishing or regenerating.

The controller test generates a real single-node mesh through the pinned core.
Applying 180 changes vertex normals while all vertex positions and the 16-triangle
count remain identical. Normals remain unit length; Undo restores the original
normals/archive, Redo restores the edited normals/archive, and applying zero
restores sharp normals. Camera and component selection remain unchanged.

Final `make ci` passed on 2026-10-16: 352 tests, zero failures, formatting, native
builds, Qt-free linkage and isolated signed bundle rebuild checks. Measured line
coverage: mesh 66/67, document 2306/2390, editor model 1394/1400, pure editor state
523/523, undo domain 97/97 and orbit camera 33/33. This does not measure inherited
C++ or native/Metal UI coverage.

## Native evidence

Reused `/private/tmp/dust3d-combine-qa/Dust3DEditor.app` with the existing
`org.dust3d.editor.combine-qa` identity and strict signature verification.
Opened an independently serialized single-node colored fixture with a future
attribute and four-byte opaque asset. Reset Cutoff discards an unapplied text
draft without creating history. Apply 180 updates the field and rendered shading,
retaining 16 triangles and selection. Save writes the cutoff and retains the
future attribute and opaque asset. Native Undo plus Save is byte-identical to the
original archive; Redo plus Save is byte-identical to the saved applied archive.

Applying 181 displays the finite 0–180 range diagnostic without changing the
saved document. Dismiss and Reset recover the field to 180. Native rendered
inspection caught a disappearing placeholder label; a persistent caption was
added and the full gate rerun. The final build reopens the saved 180-degree value,
shows the persistent label and readable Apply/Reset controls, and renders the
smoothed mesh. QA documents were saved before normal Quit for bundle reuse.

Unsupported-source display and replacement, component-switch draft refresh and
zero-apply are covered in code/tests but were not separately exercised in this
native pass. Qt GUI differential smoothing, interacting modifiers and broader
VoiceOver checks remain M3 acceptance work. Full modifier parity is not claimed.
