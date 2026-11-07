# ADR 0173: Canvas part isolation and restoration

Status: Qt modeling parity follow-up, Apple #343.

Qt activates Hide Other Parts with Shift-H in document_window.cc and routes it
through SkeletonGraphicsWidget::shortcutHideOtherParts to
Document::showAllOrHideOtherComponents. The checked-in reference document.cc
1199–1211 stops descendant traversal at a part link, even for hybrid components
with child XML. Lines 1243–1275 hide outside parts when any is visible; otherwise
they show all parts. Existing hidden flags inside the target stay unchanged.
Native inspectors previously exposed individual canvas visibility and directly
selected part-state batches, without this subtree operation.

Capture an explicit rendered component or part, or resolve one exact component
owner from current graph/part/component selection. Use literal UTF8 keys before
lookup/deduplication. Reject ambiguous, missing or unsupported membership rather
than choosing a fallback or hiding every part. Preserve the original hierarchy
failure in a typed unavailable reason. Groups walk descendant links; recognized
part links terminate traversal. Outside orphan parts still count as outside.
Show All bypasses component metadata so visibility remains recoverable.

CanvasPartIsolationTarget freezes one source-ordered visibility batch and its
CanvasAdjustmentTarget epochs. Actor publication rechecks document, selection
and constraint revisions including ABA, then applies existing setPartsState as
one transaction. Cancellation is checked before publication. A no-op adds no
history. Locked/disabled values and geometry/material preview identities remain
unchanged. Existing canvas fitting follows visibility changes; native mesh work
is not restarted for visibility-only edits.

Expose dynamic Hide Other Parts in Canvas / Show All Parts in Canvas in the
Canvas menu and part/component inspectors. Keep a separate restoration command
when needed, without duplicate Show All rows. Initially unavailable or obsolete
captured controls never acquire a later selection. Add/Origin modes and active
pointer work disable dispatch. Use the native keyboard menu path; this change
does not install Qt's plain Shift-H as an app-wide text key binding.

TDD pure model tests cover nested groups, hybrid stop rules, hidden inside parts,
orphans, flags, unsupported metadata causes, exact identity, bulk batches, no-op
and stale epochs. Copied-data store/actor tests verify one publication, exact
Undo/Redo, independent windows, unchanged preview identity/generation count and
pre-publication cancellation. The opaque-attribute assertion reads XML values,
without depending on quote serialization. No new native generation, GUI,
NSEvent, NSView, Metal-device or fault probes are added. Physical menu, keyboard,
VoiceOver and broad modeling acceptance remain outstanding. This does not establish full Qt/HIG parity.
Production core pin and runtime quarantines are unchanged.
