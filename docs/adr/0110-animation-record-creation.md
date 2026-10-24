# ADR 0110: Bind stored-animation creation to a captured document

Status: Local stored-record workflow; full M6 acceptance pending (#145).

A creation form may remain open while the document changes, closes or reloads.
AnimationCreationTarget captures the UUID and semantic revision from a successful
actor catalog observation, including an empty list; it rejects ambiguous metadata.
The targeted EditorSession overload checks load/cancellation and source epoch
before forwarding to existing fresh-ID insertion. Reopen and Edit/Undo cannot
revive a draft even when bytes become identical. Existing immediate actor methods
remain available; UI creation uses the captured-target overload exclusively.

EditorStore applies the existing accepted-load admission before dispatch, reports
accepted/rejected completion, refreshes metadata after publication and preserves
static geometry. Failed Open cannot relabel retained state as the attempted file.
Successful creation selects the new record and uses existing exact undo/redo and
Save. Original validation errors retain input and do not advance history.

New Animation is a full-width action below the inspector header, available from
valid empty/populated lists. Its inline optional-name/nonempty-type fields preserve
exact text. Only the first field requests initial focus in its own attached window.
A common canBeginDraft guard excludes simultaneous creation/name/value/parameter
forms and is rechecked in each action callback. No inferred type catalog, timing
defaults, parameter defaults or generator support is offered as accepted behavior.

TDD started with missing target/overload compile failures. The first actor run
also caught an incorrect test assumption about UUID formatting; the assertion now
checks the inherited brace-wrapped UUID format explicitly. Six actor/store/render
tests pass: fresh selected identities, history/reopen, opaque XML, source retirement,
ambiguous catalog/unloaded rejection, exact UTF-8 name, invalid-type retry, retained
failed-Open isolation and owned empty/ready/stale form renders. Full make ci passes
45 support tests and 1014 XCTest cases (122.573 seconds), formatting, coverage gates,
Qt-free linkage and isolated bundle/signature checks. AnimationCreationTarget.swift
measures 9/9 executable lines and EditorSession.swift 342/342. These scoped counts
do not prove whole-shell coverage or native input behavior.

See ../animation-record-creation-verification.md for inspected states and limits.
Catalog-specific controls, live keyboard/VoiceOver, Qt/native interoperability,
native evaluation/playback/audio and full M6 remain open. No protected app control,
production pin or core #67/#69/#83/#84/#95 or Apple #199 quarantine change occurs.
