# ADR 0048: Successful empty mesh previews

Status: Accepted for the native editor prototype.

A lone isolated loop with fill disabled is a legitimate empty result. Do not
infer that result from graph heuristics or reinterpret generic generation
failures. Consume the reviewed core's explicit NO_GEOMETRY status through
MeshLoader.loadIfPresent, returning nil only for that result and preserving all
other statuses/diagnostics. Keep load(data:) strict for existing nonempty callers.
The exact core revision remains authoritative in Package.swift/Package.resolved.

The preview actor returns optional copied geometry. Current nonempty output
uses succeed; current empty output uses a request-checked succeedEmpty that
clears retained geometry and increments revision. Cancellation and request
identity checks prevent old empty results from erasing new state. Genuine
failures retain the last successful mesh as stale. Document edits, archive
persistence, selection and undo remain independent from derived preview state.

Use a pure snapshot description and small native placeholder view to distinguish
unopened, newly empty, excluded and successfully empty documents. The production
placeholder can be rendered without loading Metal. This establishes static
readability, not native input, full GPU presentation or accessibility acceptance.

The core dependency is reviewed separately: twelve portable debug and sanitizer
contracts, Linux/macOS CI, malformed input and degenerate generation remaining
failures, owned buffers surviving empty loads and refilling. The Apple regression
must include a lone loop without the unrelated model used by the earlier fixture.
