# Automatic preview rotation

Issue #326 ports Qt's View rotation action. Reference source:
`application/sources/scene_widget.cc:1330`, `toggleRotation`, advances Y by
8 sixteenth-degree units every 42 milliseconds. Native View → Rotate Preview
Automatically is opt-in and belongs to the focused document window.

The SwiftUI value is passed into the existing MeshViewport boundary. A small
AppKit binding observes only its own window and application activation, plus view
visibility/detachment. Pure timing and eligibility code contains no AppKit state.
An elapsed-time driver runs at approximately 42ms intervals, rechecks eligibility
before each update, and changes only camera yaw. Reduce Motion suppresses the
turntable, as recommended by [Apple's environment-value documentation](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion).
View hiding uses [AppKit's documented lifecycle callbacks](https://developer.apple.com/documentation/appkit/nsview/viewdidhide()).

## Automated evidence

- Three timing/policy tests first reproduced 11 assertion failures against empty behavior.
- 26 focused tests pass for timing/policy, timer cancellation/deallocation, reset
  after direct input, detached viewport lifetime, window-local store preference,
  empty/failed previews, camera commands and material renderer adoption.
- Timing tests compare different callback frequencies against the Qt rate. A gap
  over 250ms, invalid clock value or non-increasing time resets the interval to
  prevent a catch-up jump after suspension or a long rendering stall.
- The driver uses weak ownership and a cancellable task. AppKit notifications stop
  scheduling when unavailable; every timer callback also rechecks eligibility.
- The production core pin and document archive/Undo state are unchanged.

## Remaining acceptance

The tests do not establish physical menu discoverability, pointer/keyboard
interaction, VoiceOver, visible rotation smoothness, platform notifications on real
activation/minimization or live changes to Reduce Motion. Run these on an unlocked
Mac using a separately identified QA bundle, preserving the existing QA app and
unsaved data. Confirm pause/resume without jumps, direct drag pause, pan/zoom/fit,
renderer replacement, close/reopen, and independent preferences across windows.
This is incremental preview parity, not full Qt or Apple HIG acceptance.
