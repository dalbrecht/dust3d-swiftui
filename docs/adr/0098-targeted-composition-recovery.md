# ADR 0098: Route composition cancellation to an exact process

Status: Local full gate passed; automated review and native delivery pending. Refs #56, #248.

## Decision

Replace the argument-free composition command with
`--cancel-reference-composition PID`. Share the bounded UUID/PID decoder with
recovery copies, in its own service file. Require a canonical positive Int32 PID,
a supported editor identity and the expected notification name before scheduling
any work. Do not accept document paths, bytes or arbitrary commands.

Use a new fixed notification name ending in `.v2`. Old receivers ignore metadata,
so adding a PID to the old name would still contact them. Versioning the name
keeps those binaries outside this protocol. New receivers ignore legacy names and
other PIDs, including processes with the same reusable bundle ID. The existing
protected QA instance and bundle are neither contacted nor overwritten.

Admit at most one pending cancellation task. Log the correlation UUID and accepted
cancellation/refusal; duplicates report alreadyPending. Keep the existing newest-
presentation rule and refuse while Apply is busy, without falling back to another
window. CLI output proves dispatch only, not cancellation. This is local routing,
not authentication against another process belonging to the same user.

## Evidence and limits

Two regression tests failed before the change: the untargeted command was accepted
and the notification still matched the legacy broadcast name. Twenty-five focused
recovery tests now pass, covering strict CLI parsing, version-name isolation,
same-bundle/wrong-PID admission, malformed metadata, bounded request admission,
newest-sheet routing and busy refusal. Copy receipts retain their PID/UUID contract.
No distributed notifications were posted and no product-window control was used.

The shared decoder/gate moved out of copy-specific code so both recovery receivers
use the same small validated boundary. The full local gate and measured coverage
remain required. Native notification delivery, held-gesture handling, VoiceOver,
unsaved-copy recovery and full M1/M2/M8 acceptance remain open. Do not retrofit or
probe the protected older executable, use its legacy cancellation helper, change
the production core pin or lift a quarantine. No UI appearance change is claimed.

## Pure sender/receiver contract

The first implementation gate passed 36 support checks and 935 XCTest cases
(119.780 seconds), with formatting, coverage, Qt-link and isolated packaging.
A follow-up extracts a pure dispatch plan so tests verify the actual sender
payload against the actual receiver decoder without posting notifications.
Application launch, typed rejection, unsupported bundle identities and invalid
constructed targets are covered. Both commands round-trip only to the intended
process; acknowledgements preserve PID/UUID and distinguish dispatch from success.

Twenty-seven focused cases pass. The dispatch plan measures 47/47 lines and 22/22
regions; the shared decoder/gate measures 35/35 lines and 14/14 regions. Swift
branch outcomes are not instrumented. The executable entry point now only launches
the app, posts a prepared request, prints output or exits with a typed error.
Those native effects and the actual delegate notification callback remain manual
boundary gaps; do not report whole-entry-point coverage or native delivery as
verified. The final full `make ci` gate at f1d53f02 passes 36 support checks and
937 XCTest cases, zero failures (118.970 seconds), formatting, coverage, Qt-link
and isolated packaging/provider checks. Final documentation does not change
tested code. Pure planner and decoder/gate retain the measured coverage above.
