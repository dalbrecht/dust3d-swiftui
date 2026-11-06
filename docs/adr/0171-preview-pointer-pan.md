# ADR 0171: Shift-drag preview panning

Status: Qt modeling interaction parity follow-up, Apple #367.

The Qt reference `application/sources/model_widget.cc` maps Shift-drag to
screen-space translation using twice the point displacement divided by each
viewport dimension. Native previews already provided bounded pan commands but
mouse dragging always orbited. Add Shift-drag panning to the existing camera.

AppKit points use upward-positive y, so the normalized delta is (2dx/width,
2dy/height). Preserve the native camera's established ±1.5 offset envelope;
Qt uses ±1.0. This implements the reference interaction and normalization without
changing existing native menu-command bounds. Ordinary dragging retains dx/-dy
orbit behavior. Reject nonfinite deltas and invalid pan dimensions. Normalize in
Double and bound each delta by the complete offset span before Float conversion.
Camera rotation, zoom, document data and undo history remain unchanged by panning.

Keep generated-rest picking's four-point threshold and full first drag delta.
Any Shift intent irreversibly suppresses that press's click, including motion
below threshold or a return to the original point. Releasing Shift can resume
orbit, but never restores click eligibility. New presses restore ordinary picks.
The current source/presentation gates, camera epochs and source leases remain.

Pure camera projection tests check screen-space direction, dimensions, bounds,
invalid input and unchanged orbit/zoom. Pure gesture tests check click suppression,
threshold and subsequent press reset. AppKit handlers only extract modifiers,
point displacement and viewport size. No new GUI, NSEvent, NSView, Metal-device or
native generation probes are added. Physical pointer, keyboard/VoiceOver and
rendering acceptance remain outstanding; no full Qt/HIG acceptance is implied.
