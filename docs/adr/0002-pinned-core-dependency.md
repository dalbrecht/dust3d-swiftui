# ADR 0002: Consume the maintained core as a pinned source package

Status: Implemented for review.

The viewer uses the `Dust3DEngine` SwiftPM product from
`https://github.com/dalbrecht/dust3d-core.git`, pinned to an exact commit in
`Package.swift` and `Package.resolved`. Those files are the authoritative current
revision and must advance together through reviewed dependency PRs. Source
consumption avoids introducing an unproven stable
binary ABI or a developer-specific CMake search path. The core's SwiftPM package
and CMake build share the same implementation and explicit target boundaries.

The native C ABI implementation and implementation-only module maps are removed
from the Apple repository. Inherited upstream/Qt source trees remain as reference
history, but are not native package targets. The core repository is now the single
source of truth for native engine changes. Updates use paired PRs, an exact pin,
core contracts/sanitizers, Apple tests and packaging verification.

Apple CI checks Swift formatting and native source/link boundaries. C++ adapter
formatting and portable builds belong to core CI. The viewer bundle identity,
rendering, controls and read-only behavior remain unchanged. Its packaging script
delivers the app ZIP; standalone engine SDK packaging belongs to the core project.

Keep the initial source integration until document/ABI requirements stabilize.
Versioned checksummed XCFramework releases remain a later distribution milestone.
