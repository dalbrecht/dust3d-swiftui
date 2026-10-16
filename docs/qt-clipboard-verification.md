# Qt clipboard verification

Full `make ci` passes 264 XCTest tests, formatting, builds, coverage and Qt-free linkage. Swift line coverage: mesh 66/67; document 1909/1986; editor model 1067/1073; pure editor state 453/453 and undo 97/97. Inherited C++ coverage is not measured. Eight focused XCTest cases pass. TDD first failed on the missing snapshot initializer, text-payload initializer, session text-paste/dual-copy APIs and dual-representation provider. Tests then verify:

- Exact canvas XML bytes and unknown extensions survive archive wrapping and reopen, including rebased Data slices.
- Malformed/wrong-root XML, duplicate containers, entity declarations, excessive depth and >16 MiB data reject; existing document validation handles finite bounded geometry.
- Empty snapshots and missing parts cannot become clipboard fragments; invalid tokens reject.
- Text imports select all included nodes. Repeated successful text pastes advance placement, failure preserves redo/bookkeeping, Open resets placement and Undo restores exact original bytes.
- Native Copy retains reference-image asset bytes while text remains asset-free. Native transport selection and the text XML refer to the same immutable fragment.
- The AppKit provider serves distinct native and text bytes, ignoring unadvertised types. Controller text Paste publishes one document change and preview; unrelated text causes a typed error without modifying document/history or notifying a write.
- Capsule XML text generates nonempty pinned-core geometry; text exported from the resulting native selection generates the same triangle count and exact undo/redo remains available.

Source comparison used inherited `application/sources/document.cc` Copy/Paste and `dust3d/base/snapshot_xml.cc` parsing/serialization. This establishes the transport shape, not a completed Qt GUI transfer. The Mac was locked during the native interaction attempt, so actual PasteButton format preference, keyboard/text-field routing and native↔Qt clipboard interaction remain manual acceptance checks. No new design baseline or screenshot claim is made. See [ADR 0027](adr/0027-qt-clipboard-text.md).
