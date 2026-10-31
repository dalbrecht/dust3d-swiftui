# ADR 0096: Headless static OBJ export

Status: locally implemented; reviewed dependency integration remains required.
Tracking: #186, M7 #146.

## Decision

Add a SwiftPM Dust3DExport executable that shares ObjExportService and
ObjExportFileService with the editor. Parsing and the immutable runner remain
separate from process stdio/signal ownership. No GUI scene starts. One explicit
DS3 input and OBJ output are admitted per invocation; relative paths and legacy
`-output` are supported. Existing bounded archive reads, source-aware geometry,
C ABI ownership and coordinated atomic writes remain authoritative.

Use no new dependency: a small bounded argument grammar is sufficient. Pulling
in ArgumentParser or shelling out to the editor would add dependency/runtime
surface without helping this one-command contract. Batch grammar may justify a
separate decision later.

## Stdio, errors and cancellation

Duplicate stdout for the sole JSON success receipt, then redirect process stdout
to stderr before engine work. The inherited C++ logger writes std::cout; simply
using Foundation standardError for Swift progress cannot keep receipts clean.
Keep redirection until process exit so native buffered teardown logs stay on
stderr. Help runs without native work or redirection. Stderr may mix structured
JSON lines with inherited text. Failures preserve phase and original cause;
reporting failure after commit identifies the committed destination.

Install a Dispatch SIGINT source and cancel the export task from it. Darwin's
SIG_DFL is a valid null handler: retain it as optional, restore it during cleanup,
and never implicitly unwrap it. Native synchronous work is not preemptible.
Pre-commit cancellation returns 130 without replacement; a committed receipt
remains success after late cancellation. SIGTERM retains OS semantics.

## Evidence and limits

Parser tests reject ambiguous/unsupported requests. Real subprocess tests export
Capsule (80 faces), decode the entire stdout as JSON, verify source preservation,
replace an owned existing OBJ, retain original files on malformed/missing input,
and send SIGINT during a held coordinated write. The subprocess tests caught a
real null-signal-handler startup crash before its fix. Runner tests cover original
stage/cause propagation, pre-cancellation and late successful commit semantics.
The complete local gate and measured coverage are recorded with the issue.

This is geometry-only export and a single-file command, not full M7 acceptance.
Materials, textures, bones, animation, GLB/FBX/WAV, batch failures and independent
full-format re-import remain required. The SDK/Core stages must be reviewed and
pinned before the production dependency path can build this local stack.

The isolated-local-core `make ci` passed: 919 XCTest tests and 50 build-support
tests, configured coverage gates, formatting, Qt checks and bundle rebuilds.
Core revision: 5eb6db7a7bbb3e39c2a4d4e19335cd50a4469d94. The production pin
and Package.resolved bytes remain unchanged. LLVM coverage measured parser
55/55 lines (42/43 regions), runner 32/32 lines (19/19 regions), and process
application/signal/stdio boundary 88/112 lines (45/58 regions). The latter is
78.57%, below the general infrastructure target: descriptor exhaustion, broken
reporting streams and defensive fallback paths remain unverified; do not claim
95% CLI boundary coverage. Track that residual under M8 #147. An explicit
`otool -L` inspection additionally verified the new CLI binary has no Qt linkage;
the inherited script currently enumerates apps/extensions, not this new product.
