# ADR 0030: Guard native save snapshots

Status: Accepted

## Decision

Keep SwiftUI DocumentGroup and the complete native File menu. At FileDocument serialization, reject a snapshot while its editor has an outstanding primary operation or after a newer document value has published. Return typed LocalizedError diagnostics with a failure reason and retry suggestion; do not supply stale bytes to FileWrapper.

EditorFileDocument remains a value containing immutable archive Data. Copies of one document share only an EditorSaveState synchronization token. Each data assignment publishes a fresh UUID version; each value retains its corresponding version. Undo back to identical bytes still creates a new version, so an old snapshot cannot regain validity through byte equality. Separate document initializations have independent tokens; native Duplicate and Save As were checked independently.

The token uses OSAllocatedUnfairLock, available below our macOS 14 minimum. Its state is just version and busy flag. This supports synchronous FileDocument callbacks and Swift 6 Sendable checking without introducing unchecked Sendable conformance. An actor would require async access from a synchronous serializer; manually locked mutable class fields would need a weaker concurrency proof. There is no additional package dependency.

EditorStore announces busy state synchronously before scheduling session work. It publishes changed bytes before releasing that state. Failure releases it without changing bytes; Stop cancels publication, releases the token and removes callbacks. EditorRootView connects these callbacks to its bound file value. The toolbar uses the same availability state. Native Save/Save As/autosave all encounter the serializer check, without replacing native menu commands or maintaining another writer.

## Guarantee and limits

Validation is the linearization point for obtaining an immutable save payload. An operation already pending or a version already superseded at that point cannot return bytes. A later edit after payload acquisition is a normal concurrent document change; AppKit/SwiftUI still own coordinated file writing, dirty tracking, atomic replacement, error presentation and close handling. This is not a filesystem transaction lock held across native I/O, nor proof of disk-full or crash recovery.

The original rapid Undo/Save observation was intermittent; the short one-node native sequence did not reproduce it. Controlled tests establish explicit snapshot invariants. Native Save immediately after starting a bounded 16-megapixel image import exercised rejection and preserved the original file; retry after publication saved the current image. See [verification](../native-save-snapshot-verification.md) and #60. No core pin, C++, dependency, lockfile or CI change.
