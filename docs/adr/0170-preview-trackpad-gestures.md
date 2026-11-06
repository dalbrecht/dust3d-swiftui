# ADR 0170: Native preview trackpad gestures

Status: Apple HIG input follow-up, Apple #367.

Apple's [pointing-device guidance](https://developer.apple.com/design/human-interface-guidelines/pointing-devices)
expects appropriate standard trackpad interactions. Mesh previews previously
handled mouse drag/scroll and keyboard controls but not magnify/rotate events.
Provide native NSResponder magnify/rotate handlers over existing camera behavior.

The [AppKit event guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingTouchEvents/HandlingTouchEvents.html)
defines incremental magnification with scale factor 1+delta and counterclockwise
rotation in degrees. Map pinch to existing bounded distance zoom using
log1p(delta)/0.03; reject nonfinite values and nonpositive scale. Clamp through the
existing 1.25...20 distance envelope. Bound full turns before Float conversion.
For this 3D viewport, counterclockwise rotation maps to existing Orbit Left and
clockwise to Orbit Right. This app direction/axis policy preserves pitch, pan and
existing menu/keyboard controls; it is not an Apple-mandated 3D rotation axis.

Use NSEvent.phase to track shared magnify/rotate activity, including reinterpretation
within a sequence. Current NSResponder SDK headers deprecate generic begin/end
gesture callbacks because they are no longer delivered. Began/changed/stationary/
mayBegin activity pauses automatic orbit through the existing interaction gate;
end/cancel/one-shot none clears activity. Apply final valid ended deltas, ignore
cancelled deltas, and reset timing before resuming so no elapsed jump occurs.

Accepted gestures cancel pending clicks and replace camera input UUIDs, including
zero-delta begins, so old background picks cannot publish against a moved camera.
Lifecycle loss, source lease replacement, hiding/detaching, own-window deactivation
and app deactivation clear incomplete interaction. Only the current origin may
invalidate a shared camera epoch; obsolete views clear their local state without
spoiling newer work. Keep input lifecycle observation scoped to the view's own
window/app and retain Reduce Motion/visibility/key-window constraints.

Pure camera-math and phase/availability tests use copied values, including bounds,
invalid deltas, complementary pinches, direction and cancellation. No NSEvent,
NSView, GUI, native generation or Metal-device probes are added. These tests and
SDK compilation cannot prove physical gesture ergonomics, notifications, keyboard
focus or VoiceOver behavior. Those acceptance checks and full Qt/HIG parity remain
open; production core pin and all runtime quarantines remain unchanged.
