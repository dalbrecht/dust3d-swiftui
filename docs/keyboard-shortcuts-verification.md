# Native keyboard shortcut help (#333)

Help > Keyboard Shortcuts opens one reusable window independent of document focus. Search matches action names, displayed keys and focus descriptions, ignoring case and surrounding whitespace. No search results has a native empty state. Rows combine their action, keys and scope for accessibility; semantic text and native controls follow system appearance. This window does not install a key handler or modify command routing.

The catalog is native-only, audited against Dust3DEditorApp.swift, EditorClipboardCommands.swift, EditorGeometryExportCommands.swift, CanvasRotationMenuButtons.swift, CanvasPrecisionInput.swift, CanvasPointerSurface.swift, EditorRootView.swift, WorkflowReplayView.swift and AnimationAuthoringControls.swift. Keep it synchronized when those bindings change. Export Command-Shift-E means OBJ specifically; other export actions have no such binding. Existing selection/working-state eligibility still applies. System-provided File and Window shortcuts remain discoverable in their menus; no Qt-only bindings are advertised.

Apple's [macOS guidance](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos) calls for menu access to commands and support for keyboard workflows. This feature adds discoverability; it does not establish complete HIG acceptance.

Verification: search behavior first failed to compile with the absent API. Focused and full gate results are recorded in the delivery evidence. Physical Help menu invocation, window reuse, search keyboard navigation, VoiceOver pronunciation of key symbols, resizing, contrast and older-macOS acceptance remain outstanding. No existing QA app is controlled or retrofitted.
