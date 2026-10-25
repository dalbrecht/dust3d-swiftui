# ADR 0113: Install XPC peer requirements before activation

Status: prepared SDK foundation for #270, not an embedded engine service.

## Decision

Use macOS 13+ Foundation peer-requirement APIs, available within this project's
macOS 14 minimum. `HelperXPCPeerFactory` creates suspended service/endpoint
connections and anonymous listeners. Each receives its requirement exactly once
before caller activation. Callers retain exclusive configuration/lifecycle
ownership, set interfaces/handlers/delegates and invalidate their objects; they
must not reset signing requirements. Do not set listener requirements on the
singleton service listener, where Foundation documents an assertion failure.

Reuse the pure #269 identity policy and shared ASCII identifier validation.
Compile each constrained expression with Security before calling Foundation APIs
that raise Objective-C exceptions for malformed requirements. Retain original
Security parser status/description; no default/fallback/discovery is added.
Factory methods do not resume a connection or listener and do not execute code.

XPC enforces the expression against actual messaging peers rather than relying
on a PID lookup or assuming that a static file check binds a later launch. A
signed-team expression checks Apple anchoring, identifier and team. A development
expression pins an exact CodeDirectory hash: callers must provision that pin from
their trusted expected ad-hoc build, not learn it from an untrusted candidate.
The factory does not independently copy peer signing metadata; static policy
inspection remains a separate boundary. This is not a Developer ID/notarization,
launchd packaging, transport framing/resource quota or sandbox policy.

The local SDK's `NSXPCConnection.h` specifies requirement installation before
`resume`, rejection of messages from mismatched peers, and anonymous-listener
rejection before delegate consultation. The [Apple requirement-language guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html)
provides the constraint syntax. No package dependency or production pin changes.

## Acceptance

Missing-factory test compilation preceded implementation. Nine focused XCTest
cases pass, including existing signature policies and new suspended endpoint/
service/listener configuration, exact service naming and invalid-input preflight.

The auto-discovered build-support contract compiles a fresh owned Swift executable
inside the single shared build root, explicitly ad-hoc signs only that disposable
fixture without credentials, reads its test-only CDHash, and executes it. Its
anonymous XPC endpoints belong to that process and contain no engine:

- Matching peers echo exact three-byte data.
- A wrong server pin rejects replies at the connection.
- A wrong client pin rejects the incoming connection before the listener delegate
  is consulted (the accepted-connection count stays zero).

All failures in the fixture exit normally with diagnostics; it uses no fatal
assertions, forced signals, crash probes or arbitrary object-graph decoding.
Original proxy errors remain diagnostic values. Timeout retires owned objects,
not another application. Temporary binaries are removed after completion and the
shared compiler cache is retained. The contract skips non-macOS with an explicit
platform reason; this run establishes macOS arm64 evidence, not Intel execution.

Initial full gate passed 46 support + 1033 XCTest cases. After making the signing
precondition explicit and preserving proxy diagnostics, the final full `make ci`
passes 46 support + 1033 XCTest cases (122.819 seconds), strict formatting,
configured coverage, Qt-link and isolated bundle-rebuild/extension checks. Final
pure policy coverage is 54/54 lines, 29/29 regions. Factory coverage is 29/32 lines,
12/14 regions; unusual Security parser/nil-result guards remain unforced. Swift
exports no branch outcomes. SDK aggregate coverage is 2852/2910 lines. No
whole-engine, signed-release or isolated-engine acceptance follows.

## Remaining work

Implement the real embedded service, bounded typed frame exchange, authoritative
request/revision admission, async cancellation/error/lifecycle ownership, sealed
bundle packaging, expected release identity, entitlements/sandbox decision,
notarization and parent-death/resource policy before production adoption. Separate
process isolation is not established by an anonymous echo inside one owned test
process. Preserve core #123 and all GLB/writer/fault/animation quarantines.
