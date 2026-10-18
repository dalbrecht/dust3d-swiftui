# ADR 0071: Immutable runtime build identity and QA packaging

Status: locally verified for #136; automated PR review and remote CI pending.

## Decision

Embed bounded JSON in the executable's Mach-O `__TEXT,__dust3d_build` section.
The canonical Swift wrapper first resolves dependencies with the same scratch/cache
configuration as its build, then generates a content-addressed linker input outside
the source tree. Resolution failure stops the primary build before identity capture.
This ordering prevents a manifest update from embedding a stale Package.resolved
core pin while SwiftPM selects a newer core for the executable. It records the source Git revision, dirty flag, a SHA-256 digest of
tracked/unignored file identities and contents, and the exact core revision from
Package.resolved. Distinct dirty source edits produce distinct linker input paths,
so a shared dirty boolean cannot accidentally reuse an old link result. Symlinks
are hashed as links; the generator does not follow them outside the checkout.
Gitlinks contribute their recorded revision rather than vendored directory contents.
This is build provenance, not a cryptographic attestation of the compiler or host.

At startup, both apps force one immutable capture from the loaded executable image.
The reader copies at most 4096 bytes through the macOS loader's section API and
validates schema, hexadecimal revisions and digest. It never reads an on-disk
executable or bundle plist to obtain source identity. Process ID, capture time and
launch bundle ID remain separate fields; capture time is not kernel process start
or build time. Missing/invalid metadata remains unavailable with its original cause.
Direct SwiftPM builds without the wrapper can run, but cannot claim known identity.
Failure to generate optional provenance leaves the original diagnostic visible and
continues the build without an identity section.

About windows expose selectable, accessible diagnostic rows in both apps. The
window title, menu item and header use the distinct QA name selected from the
captured launch bundle ID, without rereading mutable bundle metadata. Both
`--logs` and `--telemetry` stream the owning app’s distinct subsystem so canonical
and QA processes with the same executable basename do not mix their events. Preview-cache reset, recovery and startup loggers all derive their subsystem from
the same immutable captured identity. Startup logs carry source/core/digest/dirty fields and process ID without document paths.

`--editor-qa` reuses org.dust3d.editor.combine-qa and separate default output/archive
directories. QA bundles remove copied Quick Look/thumbnail providers; canonical
org.dust3d.editor remains their sole owner. Every packaging mode checks the exact target executable path before compilation.
Canonical editor builds compile the app and both preview products before the final
check and first bundle mutation. The provider helper only packages prebuilt products
and checks the owning editor again before each provider copy. A target launched
during any build, or a provider compilation failure, leaves the old bundle intact. It does
not terminate editors or conflate other QA/canonical paths. Launch verification
also checks that exact executable rather than any process with the same basename.

## Alternatives

Reading Info.plist when the About window opens would misidentify an older process
after its bundle is rebuilt. Capturing plist values once is better, but still reads
replaceable files rather than the loaded image. Generating Swift sources into the
checkout would add source churn and complicate direct SwiftPM builds. A native
linker section needs no new dependency and keeps generated inputs in the build cache.
No core adapter or package revision changes are required.

## Verification and limits

Tests cover metadata bounds/schema/fields, pure presentation and unavailable causes,
exact process paths (including spaces and /tmp aliases), clean and distinct dirty
build inputs, ignored/untracked/deleted files and missing Git/core metadata.
Resolver-ordering regressions model an updated manifest with an old resolved pin
and require the newly resolved core identity before linking; resolver failures
retain the original cause and never produce metadata or invoke the build.
A disposable macOS process uses the production reader, retains identity A after
its executable is atomically replaced, and reports identity B after restart.
The package rebuild gate checks the stable QA identity, signed bundle and absence
of preview extensions, including cleanup of copied provider directories.
Native About-window inspection and the complete gate pass with explicit residual
limits in [verification](../runtime-build-identity-verification.md). This work
supports exact-build acceptance; it does not itself close #120's modeling or Qt
comparison requirements, nor establish full M8 hardening.
