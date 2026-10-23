# ADR 0090: Native selectable node identity

Status: locally implemented and natively verified; publication pending. Refs #235.

## Context

On the clean QA editor, SwiftUI selectable node-ID text displayed the current
identity while its accessibility value retained the previous identity. A native
NSHostingView state-transition regression reproduces that stale value, fixed in
the preceding stage by recreating Text when identity changes. Fresh native reads
verified the correction. However, selecting that UUID and pressing Command-C
copied node-fragment XML. EditorClipboardCommands routes text through an NSTextView
field editor; SwiftUI selectable Text did not enter that existing route.

## Decision

Wrap only the read-only node identifier in a small NSViewRepresentable containing
an NSTextField. SwiftUI owns the immutable string; AppKit owns presentation and
transient native selection. The field is selectable, never editable, uses the
semantic secondary label color and caption font, and replaces its value only when
identity changes. Existing commands recognize its native field editor, so no
broader responder-chain interception or clipboard-policy change is introduced.
No dependency, archive, core pin, generation or undo behavior changes.

This replaces the previous identity-specific Text lifetime workaround at this
single boundary. Other selectable labels and the staged OBJ status are separate
acceptance work; this does not claim they are fixed.

## Verification

The new test first fails compilation because the bridge does not exist; the
original keyboard-copy failure was reproduced in the native QA app. The hosted
AppKit contract verifies read-only selection, a native NSTextView first responder,
exact selected range, byte-exact text transfer to a private pasteboard using the
text type advertised by AppKit, and current accessibility/active-editor values
after an identity update. Initial private-pasteboard attempts incorrectly assumed
the modern string type; diagnostics showed the field editor advertises legacy
NSStringPboardType, and the test now exercises that advertised type. It does not
write to the user's general pasteboard. The existing first/second/first identity
regression also passes with unchanged document bytes and history.

Full make ci passes 36 build-support checks and 895 XCTest cases, zero failures
and zero reported runtime skips (113.282 seconds). Formatting, coverage,
Qt-link and bundle checks pass. One shared build root is reused. The legacy pinned
core's known global stitch SVG output was restored to retained original bytes and
mtime after tests. The running QA bundle was not overwritten by isolated bundle
checks. A subsequent fresh QA process (77988) reports clean source
`2011b362df1495862eb8ee10c41ef5ccb7ba9718`, digest
`b9dfc3de67e2d474c626d11c4cfc265725e8bc10e81c99087bf9d0607bc7d65f`,
unchanged core41af7d4 and the reused QA bundle ID. Native Node1→Node2 selection
updates the full accessibility value. Triple-click selects the UUID; Command-C
and paste into an uncommitted X draft produce only that exact UUID, rather than
node-fragment XML. Reset restores X0.5. Archive bytes match the prior saved
2-node fixture and Undo/Redo remain disabled. The label's rendered appearance was
inspected; screenshots/runtime identity are retained in the checkpoint. The app
was rebuilt only after normal Quit and verified process exit.

Full VoiceOver, staged OBJ status and editor parity remain unproven. All existing
safety quarantines remain in force.
