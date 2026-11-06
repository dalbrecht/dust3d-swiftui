# Native inspector presentation (#341)

The editor uses SwiftUI `inspector(isPresented:content:)` with a per-window
`@State` binding and an adjustable column (250 pt minimum/ideal, 400 pt maximum).
The existing Selection and Animations content moves into that column. The
Animations command still selects its section and presents the inspector.
`InspectorCommands()` supplies the native focused-window visibility command;
the shortcut catalog documents Control–Command–I. The toolbar uses a system
button-style `Toggle` bound to the same state, with an Inspector accessibility
label and a stable identifier.

Primary API references:

- [InspectorCommands](https://developer.apple.com/documentation/swiftui/inspectorcommands)
- [Inspector presentation](https://developer.apple.com/documentation/swiftui/view/inspector(ispresented:content:))
- [Inspector column width](https://developer.apple.com/documentation/swiftui/view/inspectorcolumnwidth(min:ideal:max:))

## Evidence and limits

The shortcut catalog regression failed before the entry was added and passes
with the native shortcut and focused-window scope. The production visibility
control renders in both states in light and dark appearances; local artifacts
are evidence for inspection, not committed snapshot baselines.

The two-window accessibility fixture first calibrates its AX-value reader with
an unmodified system SwiftUI button-style Toggle. On this local offscreen host,
that calibration exposes no readable numeric AX value, so the state assertions
are explicitly skipped. They remain mandatory when calibration succeeds. This
is not evidence that the production control announces its state correctly.
Earlier failing old-button runs also cannot establish an accessibility
regression while that reader was uncalibrated. A mislabeled local backup was
found to contain the old Button and was corrected before final validation.

The fixture owns its offscreen windows, which cannot become key or main; it
checks that the test app stays inactive. It performs no accessibility actions,
controls no existing app, opens no document and evaluates no native geometry.

Physical acceptance remains open: resize the native column, toggle it with
Control–Command–I and the View menu in two independent document windows, verify
Animations opens the correct section, inspect narrow-window behavior and focus
restoration, and verify the toolbar name/state with VoiceOver. Full-editor
presentation and these physical interactions are not proven by control images
or the catalog test. Production core pin and all quarantines remain unchanged.
