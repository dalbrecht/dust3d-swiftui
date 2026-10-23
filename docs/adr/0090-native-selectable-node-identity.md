# ADR 0090: Native selectable node identity

Status: local implementation; native Command-C verification pending. Refs #235.

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
checks. Fresh native keyboard Copy/paste and rendered label acceptance remain
required before claiming that workflow complete. Full VoiceOver and editor parity
remain unproven. All existing safety quarantines remain in force.
