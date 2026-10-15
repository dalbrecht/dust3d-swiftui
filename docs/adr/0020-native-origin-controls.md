# ADR 0020: Native origin editing and global alignment

Accepted 2026-10-15. Tracks #41, building on the lossless origin archive foundation.

Publish the supported origin in immutable document/editor snapshots. The native inspector exposes a collapsed Document Origin group with labeled string drafts, explicit Apply/Reset, bounded validation messages and unavailable-origin guidance. String drafts avoid the numeric formatter's separate invalid-text buffer. Native text focus retains normal editing/clipboard behavior. New axis locks reset only the affected draft; unrelated unapplied fields remain intact.

EditorState constrains origin commands using per-window X/Y/Z locks, validating proposed coordinates before masking locked axes. Unknown origins cannot initialize while any position axis is locked, because there is no supported original locked coordinate to retain. Radius lock does not constrain origin initialization. Every explicit edit is one existing transaction; nodes/selection remain unchanged, and preview generation uses the existing request identity/error policy.

Extend SelectionTransform with six explicit Front X/Y and Side Z/Y alignment-to-document-origin cases. They share the existing locked/readonly-aware set-nodes transaction. Missing/unsupported targets reject atomically with unavailableOrigin; native entries are disabled in that state while local alignment remains available. Zero and negative stored origins are accepted as explicit targets. This deliberately does not reproduce Qt's fuzzy-zero/unsettled-origin guard or silently settle the origin on read; the archive already supports zero and the native UI explains the policy. Full Qt GUI parity is not claimed.

Origin markers, canvas dragging, explicit bounding-box settlement and rotated/mixed-profile Qt differential checks remain separate work. No C++/core dependency change is required. Generation failure does not invalidate a successful lossless document edit; Undo can restore the source failure state and retain the last valid mesh with an explicit stale error.
