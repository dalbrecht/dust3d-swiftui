# Native save snapshot verification

## Automated evidence

Regression-first missing-API failures preceded EditorSaveState, snapshot validation and busy publication callbacks. Five tests cover:

- Pending edits reject the old and current value copies; the newest published value saves after release.
- Superseded snapshots stay rejected after Undo returns to identical bytes.
- Separate documents have independent state; malformed archives are rejected at initialization.
- Native NSError bridging includes an explicit failure reason and retry suggestion for both typed errors.
- Store add/Undo publication order and controlled failing/cancelled imports release the barrier without partial bytes.

The full `make ci` gate passes 294 XCTest tests, formatting, strict native builds, measured coverage thresholds and Qt-free linkage. New save-state helper: 34/34 lines (100%). FileDocument wrapper: 18/26 lines (69.23%); native read/write configuration and wrapper boundaries are exercised manually rather than claimed as unit covered. Existing mesh 66/67, document 1909/1986, editor model 1198/1204, pure state 461/461 and undo 97/97 remain unchanged. This does not measure inherited C++ or prove 95% whole-app coverage.

## Native evidence

Used the existing QA bundle identity and disposable files. A settled one-node Save wrote the edited model. The short rapid Undo/Save sequence on the preceding master restored its baseline correctly; the earlier timing symptom was not deterministically reproduced by that sequence.

With the snapshot guard, inspected the full native File menu: Open Recent, Close, Save, Save As, Duplicate, Rename, Move To, Revert To and Share remain present. Saved an empty baseline, duplicated it through the native command, and saved the duplicate independently.

Imported a synthetic valid 8192×2048 PNG (16 megapixels, 71,515 encoded bytes) into the original and immediately sent Command-S. Native Save showed an error and the original and duplicate both remained byte-identical to their saved baselines. After the import settled, retry Save succeeded; independent archive/PNG-header inspection confirmed the stored 8192×2048 image. Switching to the duplicate and saving after the original changed also succeeded with its exact original bytes. Native Save As wrote another byte-identical independent copy.

The first Save alert omitted the underlying reason. After adding NSError failure/recovery metadata, repeated native open/import/immediate Save. The alert explicitly said an edit was still being applied and instructed retry; the on-disk baseline again remained unchanged. The final source trims duplicate retry wording only. After unlocking, dismissed the alert and saved the settled import (295,295 bytes). Undo followed by settled native Save restored the original 180-byte archive exactly. Redo followed by settled Save restored the applied archive byte for byte. A final Undo/Save restored the disposable fixture to its original baseline. No process was killed or document discarded.

## Remaining scope

A physically timed native obsolete-snapshot race, disk-full/interrupted writes, close-cancel while editing, broader autosave/version recovery, VoiceOver and Qt GUI differential acceptance remain unverified. The controlled stale-copy tests cover the version invariant, not every AppKit scheduling path. This change does not finish M1 or M2 acceptance. See [ADR 0030](adr/0030-native-save-snapshot-guard.md).
