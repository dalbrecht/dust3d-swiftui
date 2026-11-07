# ADR 0176: Subtractive graph selection

Status: Activated Qt modeling parity follow-up, Apple #343.

Qt SkeletonGraphicsWidget::mousePressEvent (application/sources/
skeleton_graphics_widget.cc1736–1756) removes hovered graph objects with Alt.
checkRangeSelection at2670–2724 force-removes marquee hits with Alt; Control
preserves unhit prior selection. These are wired pointer workflows. Native
selection previously supported replace/add/toggle only.

Use Command-Option-click and Command-Option-marquee to remove hits while retaining
other explicit picks. Command is the existing native membership modifier;
Command-Option takes priority over toggle and Shift-add. Option alone retains
existing behavior. This adapts the useful Qt Control-Alt subtraction intent;
it does not reproduce Alt-only marquee clearing all selection. Modifier intent
is copied at press time, using the existing primary/context routing and pointer
cancellation boundaries. Subtractive node clicks never begin geometry drags;
subtractive double clicks do not invoke Select Whole Part. Non-graph origin
handles retain existing modifier behavior. Help lists the gesture.

EditorState.removeFromSelection validates every supplied exact UTF-8 source
identity before mutation, then removes independent explicit node/edge picks.
It never infers endpoints or selects an unselected hit. Empty/no-hit subtraction
preserves selection epochs, inspector and reveal state. A real removal uses the
existing atomic selectGraph route once. The actor and store expose the same
selection-only operation; archive bytes, undo/redo, geometry/material identities
and preview generation remain unchanged. Existing visible center/stroke marquee
hit testing is reused, including crossing edges and degenerate stroke handling.

TDD covers missing APIs, mixed removal, exact identities, atomic invalid inputs,
no-op inspector/reveal preservation, actor history, copied modifier precedence,
store publication/preview identity and crossing-edge marquee behavior. Existing
pure pointer cancellation/context regressions remain in the focused gate. No
new GUI, NSView/NSEvent construction or native-generation probes are introduced.
Source compilation and copied input tests do not prove physical pointer,
keyboard/VoiceOver, HIG or full Qt parity. Those acceptance gates remain open.
Production core pin and runtime quarantines are unchanged.
