# OBJ export UI verification (#281)

Review mode: full. Scope: new original-geometry OBJ command, toolbar action,
feedback strip and document-window destination boundary. Framework/style: native
SwiftUI semantic colors, system controls and SF Symbols; narrow AppKit sheet.
No existing app redesign or new styling dependency.

| Category | Evidence inspected | Result |
| --- | --- | --- |
| Typography | Canonical status view, sample light/dark encoding, finishing and warning output; byte count uses monospaced digits, destination truncates in the middle, warnings wrap | Clear in inspected renders |
| Surfaces | Inline strip and divider, 40-point Cancel/Dismiss content height; no canvas-covering toast | Clear in inspected renders; live hit testing not verified |
| Animations | No custom motion/transitions; static phase text accompanies system progress | Clear source inspection; native progress timing not measured |
| Icons | System export/checkmark symbols with inherited semantic styling | Clear in inspected renders |
| Performance | Stateless feedback view, actor-owned encoding, one owned export task and no custom per-frame work | Clear source inspection; live performance not measured |

No actionable interface-polish findings in the inspected scope.

## Considered but rejected

| Location | Candidate | Rejected because |
| --- | --- | --- |
| Feedback strip | Overlay toast | It would obscure the node canvas and detach warnings from the export result |
| Cancel/Dismiss buttons | Custom hover/press animation | Native controls already provide platform feedback; custom motion adds repeated distraction |
| Completion row | Finder action | It adds an OS interaction beyond the requested reliable export workflow; destination is already shown |

## Evidence

The owned offscreen helper compiles `EditorOBJExportStatusView`, the canonical
phase and receipt sources directly with Swift 6 strict concurrency. It renders
choosing, encoding, cancelling, completion and warning sample states in light and
dark appearances. The helper never shows a window or panel and does not launch or
control a QA app. Samples use Capsule.obj, a 4 KiB receipt and the existing
untextured-preview warning; these are presentation samples, not captured exports.
Local images and canonical source hashes are retained under the shared build root
`apple281-screenshots` and `apple281-feedback-source-hashes.json`. No local pixel
baseline is committed or claimed as a CI comparison.

Focused XCTest runs verify injected chooser/encoder ownership, idempotent Cancel,
stop, stale-source rejection, original causes and source aliases. Separate pure
admission tests validate sheet availability and accepted/cancelled URL responses.
The native save panel is not opened by these tests. Its window/focus/Return/Escape,
security-scoped destination behavior, keyboard command dispatch, VoiceOver and
actual GPU behavior remain **not verified**. Protected QA apps are untouched.

Verdict: Approve for the inspected source/offscreen polish scope. The unverified
live interactions above remain release acceptance work; this review does not
claim full export or editor parity.
