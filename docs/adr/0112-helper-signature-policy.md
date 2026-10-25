# ADR 0112: Explicit helper signature policies

Status: prepared SDK foundation for #269, not a production worker launch boundary.

## Decision

Separate pure `HelperSignaturePolicy`/copied signing facts from a narrow read-only
macOS Security API boundary. A signed-team policy requires an Apple-generic anchor,
exact code identifier and exact ten-character signing team. It rejects ad-hoc
signing. An explicit development policy requires ad-hoc signing with no team and
a caller-trusted 20-byte CDHash. There is no default policy or automatic fallback.
The development pin is not learned from the candidate by the verifier. Restrict
configured identifiers/team strings before constructing a requirement expression;
never interpolate unrestricted values into the requirement language.

`HelperCodeSignatureVerifier` creates static code, compiles the chosen requirement,
checks strict/all-architecture validity, then independently copies and compares
signing facts. It retains the original Security OSStatus/CFError description on
rejection and performs no logging, launch, signing, entitlement mutation or retry.
Call synchronously away from the UI thread. Security is an existing system SDK
framework, not a new package dependency. Prefer it to launching/parsing `codesign`,
which would add process and text-format boundaries and lose typed OS causes.

Pure comparison is not authentication: only the platform operation establishes
code integrity and Apple anchoring. Even that operation verifies the file at one
instant. It does not bind a subsequent path-based launch, prevent replacement,
validate expected parent-bundle sealing, prove Developer ID/notarization, impose
sandbox/parent-death policy or distribute trusted configuration. Signed-team
requirements intentionally do not claim a Developer ID-only certificate policy.
The single development hash is validated across architectures; this stage verifies
a thin arm64 development helper, not universal ad-hoc acceptance.

No app launches or production core pin changes. Trusted launch integration and
containment remain core #123 and M8 gates. All quarantines remain intact.

## Verification

After correcting standalone compiler cache/framework setup, new policy tests failed
on missing policy/identity APIs before implementation. Six focused XCTest cases
pass. They cover exact team/identifier/ad-hoc/hash matching, configuration and
requirement-language input rejection, invalid URL preflight and original missing-
file Security errors without reading protected app state or changing signatures.

A separate strict-Swift-6 local checker inspected the freshly built core SwiftPM
worker without executing it. The recorded development CDHash accepted; an incorrect
pin and the signed-team requirement both rejected with original OSStatus -67050
and nonempty framework cause. The helper was ad-hoc signed with no Team ID. This
is controlled local integration evidence, not CI coverage or release signing.

Fresh full `make ci` passes 45 build-support tests and 1030 XCTest cases (123.569
seconds), configured coverage, strict formatting, Qt-link and isolated build-only
packaging/extension checks. Pure policy coverage is 51/51 lines and 27/27 regions.
The thin Security wrapper's automated coverage is 14/42 lines and 8/21 regions;
local OS acceptance is separate and unusual framework/nil-result guards remain
unforced. Swift exports no branch outcomes here. SDK aggregate coverage remains
2820/2875 lines; no whole-engine, OS-failure or distribution acceptance is claimed.
Existing legacy pinned ordinary fixtures retain their documented SVG writer side
effect; this gate is not claimed filesystem-side-effect-free. No new unsafe
fixture, fault/crash probe, protected QA control or human interaction was used.
