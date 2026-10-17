# ADR 0043: Native part modifiers and unattended visual QA

Status: Implemented for review. Tracks #85 and M3 #62.

Expose the reviewed five shape flags in the part inspector using native toggles
for known values and explicit On/Off replacement menus for unsupported source
metadata. Each control forwards to the existing serialized controller/history/
preview command. Keep stable identifiers based on inherited attribute names and
explicit accessibility labels on replacement menus. Place menu titles above
full-width menus so both the title and unsupported source value remain readable
within the existing 250-point inspector.

Add a test-only rendering boundary and `script/render_editor_ui_qa.sh` for visual
inspection without desktop input. SwiftUI remains the source of the actual view;
a hidden test-owned NSWindow/NSHostingView provides the native drawing context.
ImageRenderer alone substitutes unsupported placeholders for native text fields,
so it cannot validate the complete inspector. Keep the artifact-exporting test
process out of the Dock, never order the window front, release the content/window
after capture and bound raster dimensions. Existing product bundle identities and
the canonical app launch script remain unchanged.

Always render known/unsupported fixtures in light/dark appearances in the tests.
Verify valid PNG output, unchanged complete document bytes and empty undo history;
then inspect emitted images manually for visual acceptance. This caught menu
truncation at the real inspector width and led to the stacked menu layout.
Generated images live in a temporary QA output directory; no pixel baseline or
reference design is inferred from this new interface.

This covers static layout and initialization behavior. It does not prove native
pointer/keyboard routing, menu selection, file-panel Save/Undo/Redo integration,
VoiceOver or Metal output. Those remain explicit acceptance work while the desktop
is unavailable. Continue reusing the existing QA app identity when native checks
resume. No package dependency, C ABI or core pin changes are needed.
