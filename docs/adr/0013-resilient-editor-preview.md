# ADR 0013: Retain the last valid editor preview

Accepted 2026-10-15. Implements the M2 preview resilience requirement in #25.

Mesh generation is derived state and must not roll back valid document edits, undo, or saving. Keep the last successful immutable mesh while a newer generation is pending or fails. Label retained output as the last valid mesh; show the actual generation error and allow retry. A successful generation replaces it and clears the stale state. Rendering failures remain a separate presentation error, because retaining a mesh cannot repair a failed Metal renderer.

Use a framework-independent generic MeshPreviewState in the editor model. Each generation receives a fresh request identity; only the current identity can complete, and completion consumes that identity. Cancellation remains best effort for inherited serialized generation. Obsolete successes and failures cannot overwrite a newer request or a cleared document. Clear retained output when opening a replacement document, removing all nodes, or closing the scene. Selection changes do not regenerate geometry. Preview retries do not create undo entries or dirty the document.

This introduces no new dependency, C ABI change, core revision, or parallel engine execution. Unit tests cover state transitions, stale failures, recovery, obsolete/duplicate completions and invalidation. Native verification covers presentation and document independence; generation latency and GPU allocation failure are separate performance/robustness work.
