# ADR 0059: Lossless component color drafts

Status: Accepted for implementation; issue #118.

## Context

The inherited color class accepts `#RRGGBB` and alpha-first `#AARRGGBB`.
Component colors already affect procedural vertex RGB, while the native C/Metal
preview explicitly forces opaque output. Qt may accept additional named colors
that this portable parser does not interpret. Editing must not normalize opaque
source metadata or silently discard alpha.

## Decision

Add a framework-free immutable eight-bit `DocumentColor`, strict ASCII hex parsing
and a separate source state: unset, valid color, or unsupported original text.
Keep XML operations in a different file. A genuine edit serializes uppercase hex,
omitting alpha only when fully opaque. Semantic equality recognizes equivalent
six/eight-digit opaque spellings and retains original archive bytes and redo.
Removing an explicit color is a separate command; absence does not promise parent
inheritance, because generation determines fallback/voted colors by component.

Route Apply/Remove through existing session/history/controller commands. Unlike
scalar metallic/roughness/glow edits, RGB changes must regenerate mesh colors.
No-op and invalid drafts must not regenerate or publish. Retain generation for
all genuine RGBA changes: inherited wrap fallback votes use `Color::toString()`
keys, so changing alpha can split color votes and affect a downstream RGB winner
even though the final preview is opaque. Do not infer generation independence
solely from the shader ignoring alpha. Store alpha exactly,
and disclose that the current preview stays opaque. Preserve descendants, assets
and unknown attributes. Unsupported/empty source values require explicit removal
or replacement; do not silently interpret them as a chosen default.

Keep transient editing/reset/conversion-issue state in a framework-free immutable
`ComponentColorDraft` value, with pure replacements tested without a display.
The SwiftUI inspector has a native color picker and hex draft, explicit Apply,
Reset Draft/Escape and Use Default Color. Picker changes stay transient until
Apply. Convert through sRGB at the narrow AppKit boundary, validate finite bounded
channels before rounding/conversion to UInt8, and reject unsupported conversions
with a visible diagnostic. Inspect at most 321 UTF-8 bytes and display at most 80 characters from a 320-byte
prefix plus an ellipsis for unsupported source text, preserving the full document
value. Repair a cut UTF-8 sequence only in the bounded display summary.

## Consequences

Native color edits produce observable RGB geometry with exact lossless history.
No dependency or core pin changes. sRGB picker conversion is tested independently;
this does not claim calibrated linear/PBR shading, transparency sorting, UV/image
materials, baking, imported GLB support or full M4/native/Qt acceptance.
