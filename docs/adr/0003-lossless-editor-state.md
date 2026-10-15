# ADR 0003: Preserve archives before exposing editor controls

Status: Implemented as the first editor foundation.

The mesh-only C ABI is not an editable document: converting its vertices back into
a document would lose graph IDs, modifiers, assets and unknown fields. Introduce
an immutable Swift archive value and command/history layer before any editing UI.
Store original bytes, preserve unrelated payload bytes, and retain unknown XML
instead of rebuilding a document from only recognized attributes.

The initial codec uses macOS Foundation XML at the Apple file boundary. It is not
a portable core document API and does not replace the core's independent validation
of input passed to mesh generation. Independent archive fixtures and native-reader
compatibility tests guard the shared format. Portable core decode/encode APIs remain
later M1 work; if promoted, replace these private archive primitives behind the
existing Swift document API rather than maintaining two evolving authoritative
writers. Unknown-field retention is a requirement of that eventual core contract.

Commands produce new document values. History retains exact snapshots, coalesces
gesture edits, restores original bytes for net-zero gestures and bounds retained
archive bytes. Saves record the exact written snapshot, so asynchronous completion
cannot mark newer unsaved edits clean. The UI will own one session/history on the
main actor; file I/O runs through an actor. Expensive document operations should
also be scheduled away from the main actor when the editor session is wired.

This increment supports node position/radius changes. It does not claim complete
graph validation, topology commands, document scene integration, autosave/recovery
or native UndoManager menus. Those follow only after their own invariant and file
compatibility tests exist. The standalone viewer retains read-only behavior.
