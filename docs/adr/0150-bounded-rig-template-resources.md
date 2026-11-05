# ADR 0150: bounded pinned rig template resources

Status: implemented and locally validated for the resource-packaging portion of #195; public review and combined archive acceptance pending.

The editor stores inherited rig intent but does not yet evaluate a native rig. The seven inherited XML templates are needed for subsequent native ownership/evaluation. They exist in already pinned core revision 48b0ce2d6d61cf58731bb0c3e14ef5965a686d68. Resource packaging does not require advancing that dependency or enabling quarantined evaluation.

Copy exact template bytes into the SDK SwiftPM resource bundle with upstream MIT attribution, source paths/revision and SHA-256 hashes. Verify known template size and hash before returning owned Data. Bound filesystem reads to 16 KiB plus one detection byte; no unbounded read or native XML evaluation is needed. Missing/damaged resources and unknown source types have explicit errors; absent, empty and None source types yield no template without reading a resource. Use system CryptoKit; no package dependency is added.

For installed apps and extensions, resolve only their installed SDK resource bundle. A missing bundle must fail rather than using SwiftPM's build-cache fallback. Command-line and test use may resolve Bundle.module. Include and verify the SDK resource bundle in app and both file-preview extension packages. Tests must distinguish installed lookup failure from command-line success and preserve the underlying read failure description.

Acceptance requires red/green resource identity/error contracts, package lookup/manifest and mock packaging regressions, full local gate, and real signed archive roundtrips. Resource identity does not establish native skeleton evaluation, weights, pose playback, hardware UI, accessibility, or Qt rig parity. Production pin and existing quarantines remain unchanged.

Local verification passed 63 build-support tests and 1,577 XCTest tests, required coverage and Qt-free checks. Installed resource hashes/provenance were checked in real signed Editor, Viewer, isolated QA and both preview-extension bundles. Six focused resource tests cover absence/None/unknown, same-length corruption, oversized/missing resources, bounded filesystem reads and installed app/extension lookup without a development fallback. The package-verifier regression also rejects same-length corruption. SDK aggregate measured coverage is 3298/3354 lines; this is not a per-file or inherited-engine coverage claim.

Template XML type identities and exact pinned-source bytes are verified. An additional native catalog comparison was omitted after automatic approval review cited the retained animation-service quarantine; no new native catalog or evaluation path was added. Native consumer acceptance remains separate.
