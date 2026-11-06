# ADR 0169: Menu access to generated rest controls

Status: Experimental local-core integration, Apple #367 / HIG follow-up.

Apple's current [macOS guidance](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos)
and [menu guidance](https://developer.apple.com/design/human-interface-guidelines/menus)
expect app commands to be accessible through the menu bar. Experimental rest mode
and Model/Bones/Weights controls previously appeared only in the workspace or
inspector. Expose their existing actions in the View menu.

Use one focused scene contract for Preview Mode and generated-rest visibility.
Mode selection is available for the current document window, including its empty
loading state, matching the existing segmented control. Model/Bones/Weights menu
commands are enabled only when Generated Rest is the active workspace, matching
the visible-preview targeting of camera/Wireframe controls. They retain stored
preferences when disabled and do not target the hidden ordinary model.

Capture document identity and presentation UUID at the root. Every command rechecks
that context before reading or writing the window's session. Document replacements and presentation round
trips cannot revive an old capture. Switching modes updates the root and refreshes
focused actions; visibility delegates to existing session properties and weight
preparation rather than writing documents or starting native rig generation.

Keep experimental menu items behind the existing GENERATED flag. Alwayscompiled
pure contract tests exercise availability, all preference getters/setters, stale
captures and preference retention without constructing FocusedValues or NSMenu.
No keyboard shortcuts are invented. Real menu/focus/Full Keyboard Access and
VoiceOver acceptance still require physical review; this slice does not claim
full Apple HIG compliance or alter native/runtime quarantine boundaries.
