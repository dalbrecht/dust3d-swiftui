# ADR 0107: Inspect stored animations with source-bound inline drafts

Status: Local native metadata UI; full M6 acceptance pending (#145).

The fixed-width inspector switches between Selection and Animations. A native
List retains byte-exact row identities. Stored type and parameter values remain
read-only; absent, empty and failed queries have distinct states and original
causes. No runtime evaluation or inferred animation catalog is introduced.

Rename and duplicate capture an AnimationEditTarget. The inline native text field
retains exact UTF-8 intent and local editor selection, submits on Return and
cancels on Escape. It requests focus only in its own attached window. A stale
document disables Apply while preserving the draft. The store completion reports
actual accepted publication so rejection cannot silently discard input. Delete
uses the same captured-target validation and existing document history.

Animation focus excludes graph cut/copy/paste/select-all/delete fallbacks. Native
editable text owns Undo/Redo, including when its manager has no available undo;
that case never falls through into document history. The AppKit boundary is the
name field and existing responder lookup; no window discovery or activation is
added. These command policies have unit coverage, but live native menu validation
and field focus remain acceptance work.

Initial missing-API tests failed before implementation. Six focused tests now pass,
covering exact text, cancel/submit intent, graph shortcut scope, undo routing,
accepted/rejected completion and owned invisible panel renders without document
mutation. Full make ci passes 45 build-support tests and 998 XCTest cases
(121.028 seconds), formatting, existing coverage gates, Qt-free linkage and
isolated bundle/signature checks. This is not a whole-shell coverage claim.
See ../animation-panel-verification.md for visual review and remaining acceptance.
No protected product app is launched or controlled. The production dependency pin
and core #67/#69/#83/#84/#95 and Apple #199 quarantines remain unchanged.
