# ADR 0109: Separate parameter insertion from replacement

Status: Local stored-intent control; full M6 acceptance pending (#145).

Set/remove deliberately supports existing parameters. The Add action needs a
stronger contract: a present attribute, even with an empty value, must never be
replaced. DocumentCommand.addAnimationParameter shares name/value validation,
checks the exact unqualified attribute, and throws parameterAlreadyExists before
publication. AnimationEdit.addParameter maps to this command. The editor actor
validates the captured row/document UUID and semantic revision before applying it,
so reopen and Edit/Undo cannot revive an old draft. Existing document history
supplies exact undo/redo; rejected insertion retains bytes and redo history.

The selected record's details include Add Parameter. Its inline name/value fields
preserve exact text, use contextual accessibility labels, and remain after rejected
publication. An empty value is valid. The name field requests initial focus; the
value field opts out to avoid competing focus requests in one form. This extends
the existing owned-window AppKit boundary without activation or window discovery.
A changed document disables Add and explains cancellation/reselection. No default
units, catalog choices or native generation are inferred from stored values.

TDD started with missing command/error compile failures. Two domain and three
actor/store/render tests pass. They cover existing empty/nonempty attributes,
case-sensitive names, invalid/reserved/qualified names, missing rows, empty new
values, opaque namespaces/children, save/reopen, exact history, corrected retry,
retained original cause and reopen/Edit-Undo target retirement. Four owned form
states were inspected along with the integrated dark panel; no product app was
launched or controlled. Full make ci passes 45 support tests and 1008 XCTest cases
(122.209 seconds), formatting, existing coverage gates, Qt-free linkage and isolated
bundle/signature checks. DocumentAnimation.swift measures 52/52 lines;
AnimationEditTarget.swift 24/24; AnimationMetadata.swift 185/190 (97.37%), retaining
previous unforced Foundation-copy/cast boundaries. These are scoped line counts,
not whole-shell or native-interaction coverage claims.

See ../animation-parameter-addition-verification.md for UI verification limits.
Animation-record creation, catalog-specific controls, runtime acceptance,
playback/audio and full M6 remain open. The production dependency pin and all
core #67/#69/#83/#84/#95 and Apple #199 quarantines remain unchanged.
