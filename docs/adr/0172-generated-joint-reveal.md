# ADR 0172: Reveal selected generated joints

Status: M5 inspection and Apple #367 follow-up.

A generated joint selected through the picker or viewport could remain hidden
under collapsed ancestors. The Qt bone manager has selected-tree scrolling in
`application/sources/bone_manage_widget.cc`; the native hierarchy also needs to
make selected joints discoverable without changing camera or document state.

Own disclosure in the document window's GeneratedRigPreviewSession. Build paths
from the validated bounded GeneratedRigHierarchy forest using original source
indices, never names or joint placement. Duplicate and canonically equivalent
names, forward parents, multiple roots and zero-axis records retain identity.
A new generation resets disclosure. An actual selection change opens the outer
hierarchy and only the selected joint's ancestors, retaining unrelated expansion.
Unchanged selection/appearance/display refresh and remount preserve manual collapse.
Explicit Reveal Selected Joint creates a fresh request for the same selection.

Use controlled DisclosureGroups and a separate bounded hierarchy scroll view.
The at-most-256-joint hierarchy uses an eager stack so expanded row IDs exist;
IDs belong to joint labels rather than expanded branch subtrees. After yielding,
the scroll task checks cancellation, source generation, selected index, exact
reveal UUID, presentation epoch and expanded ancestors. Manual disclosure changes,
selection changes, new sources, stopping and presentation changes invalidate old
requests. Disappearing views cancel their structured scroll tasks.

Expose Reveal Selected Joint alongside the hierarchy and in View > Generated Rest.
Menu dispatch rechecks current scene/presentation and joint availability. No new
keyboard shortcut is invented. Selected accessibility traits, unplaced joint
labels and keyboard button alternatives remain available.

TDD pure tests cover source-index paths, expansion, repeated reveal, source and
selection ABA, stale revisions, collapse and nil selection. Copied-rig session
tests cover remount/presentation/source guards and unchanged camera/generation;
pure menu tests cover dispatch availability. No new GUI, NSEvent, NSView,
Metal-device or native generation probes are introduced. Task.yield is not proof
of completed SwiftUI layout. Physical scrolling, focus, keyboard/VoiceOver and
rendering acceptance remain outstanding. Full Qt/HIG parity is not established;
production core pin and runtime quarantines are unchanged.
