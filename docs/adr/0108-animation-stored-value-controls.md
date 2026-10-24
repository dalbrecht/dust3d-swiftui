# ADR 0108: Edit retained animation values without evaluating them

Status: Local stored-intent UI; full M6 acceptance pending (#145).

The inspector provides a pencil action beside stored type and each editable
existing parameter. Each draft captures the exact row, document UUID and semantic
revision. Its native text field preserves retained UTF-8 text, uses Return/Apply
and Escape/Cancel, and stays visible on rejected publication. A changed document
disables Apply; canceling is still available. Successful writes use existing
undo/redo and Save, without scheduling static geometry or native animation work.

An empty string means an explicitly present empty parameter. Remove Parameter is
separate and writes nil. Stored type cannot be removed or accepted empty. No
numeric conversion, inferred units or generator defaults are imposed on opaque
stored values. Qualified and reserved attribute names remain read-only. The
public DocumentAnimationParameter.canEditName policy is shared by command
validation and UI availability so namespace declarations cannot become an editable
parameter through a second inconsistent validator.

AnimationNameField accepts contextual accessibility labels and identifiers while
retaining the existing exact-text and owned-window focus boundary. A separate
AnimationValueEditor contains draft text/submission state. AnimationPanel keeps
list actions disabled while either inline editor is open and only constructs a
value target from a current source-correlated list.

The first focused compile failed for missing value-field policy APIs before their
implementation. Five focused tests then pass: intent mapping, unqualified-name
admission, empty/removal/history/reopen preservation, rejected and replaced-source
publication, and owned offscreen forms. The full make ci passes 45 build-support
tests and 1003 XCTest cases (121.793 seconds), formatting, existing coverage gates,
Qt-free linkage and isolated bundle/signature checks. DocumentAnimation.swift
measures 50/50 executable lines and AnimationStoredField.swift 24/25 (96%); these
are scoped measurements, not a whole-editor or native interaction coverage claim.

See ../animation-stored-values-verification.md for inspected renders and limits.
Creation, parameter addition, catalog-specific controls, native catalog/runtime
acceptance, playback/audio and full M6 remain open. The production core pin and
core #67/#69/#83/#84/#95 and Apple #199 quarantines remain unchanged.
