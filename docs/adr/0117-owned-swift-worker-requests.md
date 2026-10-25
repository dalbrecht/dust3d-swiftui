# ADR 0117: Owned Swift worker requests

Issue: #277. Status: full local gate passed; public review pending.

Use the existing Dust3DWorkerRuntime product from accepted core `48b0ce2d` inside
Dust3DKit. This adds no external dependency or revision change. A separate Swift
wire encoder would duplicate the authoritative core layout; instead call its
versioned C request builder and copy frame/expected-header bytes before destroying
the synchronous opaque owner. Public values are Sendable and contain no pointers.

Parent-issued nonzero document/request identity and positive supported quotas are
validated at the boundary. Request sequencing, source epochs and authenticated
admission remain parent responsibilities. UV image identities live in one bounded
text buffer through the synchronous call; descriptor pointers never escape. Image
count/text length are bounded before retaining that text. The core validates UV
options/aliases and complete wire size before copying archive bytes. Swift does
not reconstruct UV prefix or record layouts.

Only base and UV requests are exposed. The encoder treats licensed fixture archive
bytes as opaque data: source audit confirms the selected C function calls protocol
and UV metadata codecs, not archive parsing, generation, I/O or worker launch.
Original receipt category/source/code/truncation and diagnostic bytes survive a
codec rejection; display decoding does not replace retained bytes.

Encoding is synchronous and belongs off the UI actor. Input, native frame and
Swift copies can coexist; logical quotas do not establish RSS/CPU containment.
No helper execution, collection, signing, current-document publication or real
cancellation behavior is implied. All existing feature quarantines remain.

Initial tests failed for missing Swift types, then four codec tests passed. They
cover base ownership/header/UUID byte order, UV options and opaque archive copies,
boundary rejection and original UV codec receipt. One test initially expected a
texture-specific message; the authoritative core says its UV options are invalid,
and the assertion was corrected to exact original bytes. Scoped coverage before
the final ownership-transfer assertion was 167/167 lines and 21/21 functions,
but only 45/55 regions (81.82%); Swift reports no branch-outcome metrics. ABI
mismatch, inconsistent C output and allocation failure were not probed.

Full `make ci` passes with the final input-release/Sendable-transfer assertion:
45 build-support tests, 1,029 XCTest cases with zero failures, coverage thresholds,
Qt-free linkage and viewer/editor bundle rebuilds. Mesh-library line coverage is
2922/2949. Existing native integration/boundary tests remain included in that full
suite; the four new tests execute only request codecs. There is no worker launch
or new native generation probe. Completed exact-head automated review and every
public CI check remain required before merge.
