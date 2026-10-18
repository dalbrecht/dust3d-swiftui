# Native component color-image verification

Apple #140 adds native import, retained selection and clearing to ADR 0068's
lossless document commands. The exact core pin remains `2703a17`.

## Automated evidence

Tests exercise actual PNG/JPEG/BMP/GIF/TIFF files, original PNG bytes, invalid and
truncated input, encoded/dimension bounds, encoded EXIF orientation, local regular
files, retained read/decode causes and cancellation. Controller tests cover one
undo step, unchanged geometry preview revision, retained/shared assets, exact
Undo/Redo/save/reopen, rejected malformed retained pixels, selection away/back,
replacement, explicit cancellation, superseding requests and late failure after
stop. Controlled services intentionally ignore cancellation. Real production
baking changes color pixels after import and reproduces them after reopen.

Inventory tests cover unused, ambiguous, wrong-kind, unsupported and
Unicode-distinct resources. Pure presentation tests cover absent, missing,
unsupported, brace-alias and case-sensitive references and bounded combining
sequences. Offscreen inspector tests render absent, empty, long unsupported,
missing and retained states in light/dark at the established 250-point width;
rendering never changes source bytes, history or publication counts.

The full `make ci` passes 674 tests with zero failures in 105.133 seconds, plus
formatting, build, Qt-free linkage and packaged extension/rebuild checks.
Measured line coverage: Document 3296/3384, Kit 1417/1437, EditorModel 1545/1551,
pure EditorState 534/534, Undo 97/97 and Orbit 33/33. These are Swift scopes,
not a claim of 100% inherited C++ core coverage. Local artifacts live under the
test output directory's `component-color-image/`.
Rendered artifacts are evidence, not committed visual baselines.

## Native evidence, 2026-10-18

Built the current working tree through `script/build_and_run.sh --editor
--build-only`, then packaged the disposable QA bundle under the existing
`org.dust3d.editor.combine-qa` identity. Removed its copied preview extensions
before launch to avoid duplicate provider registration. The prelaunch process
inventory contained only the older canonical editor, not this QA bundle. The
fresh QA app displayed the new image controls, independently confirming that the
old canonical PID was not the tested binary.

Opened a disposable copy of Capsule.ds3 through the native open panel. Imported a
99-byte palette PNG with the native image picker; the object visibly changed to
red. Clear retained the image row; choosing that retained row restored the image.
Toolbar Undo and Redo traversed those assignments. Save removed the Edited state;
independent archive inspection found the new `images/{id}.png` payload byte-identical
to the selected PNG. The QA app quit normally after saving.

The first build's selectable text updated visually but retained stale accessibility
text. An explicit source identity now recreates that AppKit-backed view. A second
fresh build reopened the saved textured archive, then Clear and retained-image
assignment updated the accessibility tree to the correct absent/current identity.
Escape dismissed the native image picker and returned to the unchanged assignment;
Save completed normally. Build hashes,
packaging timestamps and saved archive digest are retained locally in
`/private/tmp/dust3d-color-image-native-save-evidence.json`. These observations are
working-tree evidence, not a claim that an older process executed the final PR
commit. The corrected QA binary SHA-256 is
`c6b4e34b6325782fcd156560e0c195b4df7b6853370906b500f52a323d009b5e`; packaging and later process-start evidence are retained in
`/private/tmp/dust3d-color-image-final-qa-*`.

## Interface-polish review

- Typography: inspected 250-point light/dark output; retained IDs wrap and long
  untrusted source text is bounded. Native control labels remain readable.
- Surfaces: semantic system backgrounds/buttons and the existing inspector
  spacing; retained list is bounded and scrolls rather than expanding the panel.
- Motion: no new animation; edits and cancellation work without waiting for
  decorative transitions. A proposed animated import-to-preview transition was
  rejected because geometry and material tasks finish independently.
- Icons: one system import symbol with a persistent label. Rejected icon-only
  import/clear controls because their meaning and keyboard/AX discovery are weaker.
- Performance: background bounded read/decode/encode, metadata-only snapshots,
  lazy retained rows, bounded text and material-only refresh. Rejected eager
  thumbnails of every retained image because they could decode many large assets
  before the user chooses one.

Verdict: rendered and native pointer workflows, file-picker Escape dismissal,
save/reopen and the corrected native accessibility text pass. Full VoiceOver
navigation, keyboard activation of every inspector control, cancellation during
a long native decode and native unsupported-resource interaction remain unverified;
their pure/controller states have automated tests. No supplied pixel reference exists; no baseline is invented. The
broader #120 native modeling acceptance and M4 parity remain open.
